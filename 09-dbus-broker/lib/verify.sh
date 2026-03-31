#!/usr/bin/env bash

verify_packages() {
  local pkg
  for pkg in dbus dbus-daemon dbus-user-session libapparmor1 libexpat1 libsystemd0; do
    package_is_installed "$pkg" || die "package '$pkg' is not installed"
  done
}

verify_paths() {
  require_file "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker"
  require_file "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker-launch"
  require_file "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker-session"
  [[ -x "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker" ]] || die "dbus-broker is not executable"
  [[ -x "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker-launch" ]] || die "dbus-broker-launch is not executable"
  [[ -x "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker-session" ]] || die "dbus-broker-session is not executable"
  require_file "$DBUS_BROKER_INSTALL_MAN_DIR/dbus-broker.1"
  require_file "$DBUS_BROKER_INSTALL_MAN_DIR/dbus-broker-launch.1"
  require_file "$DBUS_BROKER_INSTALL_SHARE_DIR/release-verification.txt"
  require_file "$DBUS_BROKER_INSTALL_SHARE_DIR/subprojects.lock"
  require_file "$DBUS_BROKER_RELEASE_PROVENANCE_PATH"
  require_file "$DBUS_BROKER_SYSTEM_UNIT_PATH"
  require_file "$DBUS_BROKER_USER_UNIT_PATH"
}

verify_launcher_binary_contract() {
  strings "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker-launch" | grep -Fx "/usr/bin/dbus-broker" >/dev/null || {
    die "dbus-broker-launch binary contract mismatch: expected embedded /usr/bin/dbus-broker path"
  }
}

verify_provenance_file() {
  grep -F "DBUS_BROKER_TAG=\"$DBUS_BROKER_TAG\"" "$DBUS_BROKER_RELEASE_PROVENANCE_PATH" >/dev/null || die "provenance file missing DBUS_BROKER_TAG"
  grep -F "DBUS_BROKER_COMMIT_SHA=\"$DBUS_BROKER_COMMIT_SHA\"" "$DBUS_BROKER_RELEASE_PROVENANCE_PATH" >/dev/null || die "provenance file missing DBUS_BROKER_COMMIT_SHA"
  grep -F "DBUS_BROKER_TARBALL_SHA256=\"$DBUS_BROKER_TARBALL_SHA256\"" "$DBUS_BROKER_RELEASE_PROVENANCE_PATH" >/dev/null || die "provenance file missing DBUS_BROKER_TARBALL_SHA256"
  grep -F "DBUS_BROKER_TARBALL_URL=\"$DBUS_BROKER_TARBALL_URL\"" "$DBUS_BROKER_RELEASE_PROVENANCE_PATH" >/dev/null || die "provenance file missing DBUS_BROKER_TARBALL_URL"
}

verify_unit_content() {
  grep -F "ExecStart=${DBUS_BROKER_INSTALL_BIN_DIR}/dbus-broker-launch --scope system" "$DBUS_BROKER_SYSTEM_UNIT_PATH" >/dev/null || die "system unit does not point at managed dbus-broker-launch --scope system"
  grep -F "ExecStart=${DBUS_BROKER_INSTALL_BIN_DIR}/dbus-broker-launch --scope user" "$DBUS_BROKER_USER_UNIT_PATH" >/dev/null || die "user unit does not point at managed dbus-broker-launch --scope user"
  systemd-analyze verify "$DBUS_BROKER_SYSTEM_UNIT_PATH" "$DBUS_BROKER_USER_UNIT_PATH"
}

verify_session_service_alias() {
  local alias_path="$1"
  local source_path="$2"
  [[ -f "$source_path" ]] || return 0
  [[ -L "$alias_path" ]] || die "missing D-Bus compatibility alias: $alias_path"
  [[ "$(readlink -f "$alias_path")" == "$(readlink -f "$source_path")" ]] || die "D-Bus compatibility alias '$alias_path' does not point at '$source_path'"
}

verify_session_service_aliases() {
  verify_session_service_alias "$(dbus_service_alias_path "org.freedesktop.Notifications.service")" "/usr/share/dbus-1/services/fr.emersion.mako.service"
  verify_session_service_alias "$(dbus_service_alias_path "org.freedesktop.FileManager1.service")" "/usr/share/dbus-1/services/org.xfce.Thunar.FileManager1"
  verify_session_service_alias "$(dbus_service_alias_path "org.freedesktop.thumbnails.Cache1.service")" "/usr/share/dbus-1/services/org.xfce.Tumbler.Cache1.service"
  verify_session_service_alias "$(dbus_service_alias_path "org.freedesktop.thumbnails.Manager1.service")" "/usr/share/dbus-1/services/org.xfce.Tumbler.Manager1.service"
  verify_session_service_alias "$(dbus_service_alias_path "org.freedesktop.thumbnails.Thumbnailer1.service")" "/usr/share/dbus-1/services/org.xfce.Tumbler.Thumbnailer1.service"
}

verify_system_runtime() {
  local fragment_path main_pid exe_path
  fragment_path="$(systemctl show -p FragmentPath --value dbus.service)"
  [[ "$fragment_path" == "$DBUS_BROKER_SYSTEM_UNIT_PATH" ]] || die "system dbus.service fragment mismatch: expected '$DBUS_BROKER_SYSTEM_UNIT_PATH', got '${fragment_path:-unknown}'"

  main_pid="$(systemctl show -p MainPID --value dbus.service)"
  [[ "$main_pid" =~ ^[0-9]+$ ]] || die "system dbus.service MainPID is not numeric: '$main_pid'"
  ((main_pid > 1)) || die "system dbus.service is not running (MainPID=$main_pid)"

  exe_path="$(readlink -f "/proc/$main_pid/exe" 2>/dev/null || true)"
  case "$exe_path" in
    "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker-launch")
      ps -o comm= --ppid "$main_pid" | grep -Fx "dbus-broker" >/dev/null || die "dbus-broker worker process is not attached under dbus-broker-launch"
      ;;
    */dbus-daemon)
      log_warn "system dbus.service is still running dbus-daemon; managed dbus-broker will apply after reboot or the next controlled dbus.service restart"
      ;;
    *)
      die "system dbus.service runtime is '$exe_path' not dbus-broker-launch or dbus-daemon"
      ;;
  esac
}

verify_user_runtime() {
  local user_fragment user_main_pid user_exe
  user_fragment="$(runuser -u "$DBUS_BROKER_TARGET_USER" -- systemctl --user show -p FragmentPath --value dbus.service 2>/dev/null || true)"
  if [[ -z "$user_fragment" ]]; then
    log_warn "could not query user dbus.service fragment for '$DBUS_BROKER_TARGET_USER'; verify after next login"
    return 0
  fi

  if [[ "$user_fragment" != "$DBUS_BROKER_USER_UNIT_PATH" ]]; then
    log_warn "user manager currently points to '$user_fragment'; managed user unit will apply after next user daemon-reload/login"
    return 0
  fi

  user_main_pid="$(runuser -u "$DBUS_BROKER_TARGET_USER" -- systemctl --user show -p MainPID --value dbus.service 2>/dev/null || true)"
  if [[ "$user_main_pid" =~ ^[0-9]+$ ]] && ((user_main_pid > 1)); then
    user_exe="$(readlink -f "/proc/$user_main_pid/exe" 2>/dev/null || true)"
    case "$user_exe" in
      "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker-launch")
        ;;
      */dbus-daemon)
        log_warn "user dbus.service for '$DBUS_BROKER_TARGET_USER' is still running dbus-daemon; managed dbus-broker will apply on next login or controlled user-bus restart"
        ;;
      *)
        die "user dbus.service runtime is '$user_exe' not dbus-broker-launch or dbus-daemon"
        ;;
    esac
    return 0
  fi

  log_warn "user dbus.service is currently inactive for '$DBUS_BROKER_TARGET_USER'; override will apply at next login"
}

verify_labwc_session_compatibility() {
  local session_wrapper="/usr/local/bin/labwc-session"
  if [[ -f "$session_wrapper" ]]; then
    grep -F "dbus-update-activation-environment --systemd" "$session_wrapper" >/dev/null || die "labwc-session wrapper lost dbus activation-environment handoff"
  fi
}

verify_install() {
  verify_packages
  verify_paths
  verify_launcher_binary_contract
  verify_provenance_file
  verify_unit_content
  verify_session_service_aliases
  verify_system_runtime
  verify_user_runtime
  verify_labwc_session_compatibility
  log_info "verification completed"
}
