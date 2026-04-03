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
  require_file "$DBUS_BROKER_BUILD_PROVENANCE_PATH"
  require_file "$DBUS_BROKER_BUILD_VERIFICATION_PATH"
  require_file "$DBUS_BROKER_SUBPROJECTS_LOCK_INSTALL_PATH"
  if [[ "${DBUS_BROKER_INSTALL_METHOD:-}" == "artifact" ]]; then
    require_file "$DBUS_BROKER_ARTIFACT_RELEASE_VERIFICATION_PATH"
  fi
  require_file "$DBUS_BROKER_SYSTEM_UNIT_PATH"
  require_file "$DBUS_BROKER_USER_UNIT_PATH"
}

verify_launcher_binary_contract() {
  strings "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker-launch" | grep -Fx "/usr/bin/dbus-broker" >/dev/null || {
    die "dbus-broker-launch binary contract mismatch: expected embedded /usr/bin/dbus-broker path"
  }
}

verify_provenance_file() {
  case "${DBUS_BROKER_INSTALL_METHOD:-}" in
    source)
      grep -F 'DBUS_BROKER_INSTALL_METHOD="source"' "$DBUS_BROKER_BUILD_PROVENANCE_PATH" >/dev/null || {
        die "provenance file missing source install method"
      }
      grep -F "DBUS_BROKER_GIT_URL=\"$DBUS_BROKER_GIT_URL\"" "$DBUS_BROKER_BUILD_PROVENANCE_PATH" >/dev/null || {
        die "provenance file missing DBUS_BROKER_GIT_URL"
      }
      grep -F "DBUS_BROKER_COMMIT_SHA=\"$DBUS_BROKER_COMMIT_SHA\"" "$DBUS_BROKER_BUILD_PROVENANCE_PATH" >/dev/null || {
        die "provenance file missing DBUS_BROKER_COMMIT_SHA"
      }
      grep -F "DBUS_BROKER_RUST_TOOLCHAIN=\"$DBUS_BROKER_RUST_TOOLCHAIN\"" "$DBUS_BROKER_BUILD_PROVENANCE_PATH" >/dev/null || {
        die "provenance file missing DBUS_BROKER_RUST_TOOLCHAIN"
      }
      ;;
    artifact)
      grep -F 'DBUS_BROKER_INSTALL_METHOD="artifact"' "$DBUS_BROKER_BUILD_PROVENANCE_PATH" >/dev/null || {
        die "provenance file missing artifact install method"
      }
      grep -F "DBUS_BROKER_TARBALL_URL=\"$DBUS_BROKER_TARBALL_URL\"" "$DBUS_BROKER_BUILD_PROVENANCE_PATH" >/dev/null || {
        die "provenance file missing DBUS_BROKER_TARBALL_URL"
      }
      grep -F "DBUS_BROKER_TARBALL_SHA=\"$(normalize_sha256_value "$DBUS_BROKER_TARBALL_SHA")\"" "$DBUS_BROKER_BUILD_PROVENANCE_PATH" >/dev/null || {
        die "provenance file missing DBUS_BROKER_TARBALL_SHA"
      }
      grep -F "DBUS_BROKER_COMMIT_TAG=\"$DBUS_BROKER_COMMIT_TAG\"" "$DBUS_BROKER_BUILD_PROVENANCE_PATH" >/dev/null || {
        die "provenance file missing DBUS_BROKER_COMMIT_TAG"
      }
      grep -F "DBUS_BROKER_COMMIT_SHA=\"$DBUS_BROKER_COMMIT_SHA\"" "$DBUS_BROKER_BUILD_PROVENANCE_PATH" >/dev/null || {
        die "provenance file missing DBUS_BROKER_COMMIT_SHA"
      }
      ;;
    *)
      die "DBUS_BROKER_INSTALL_METHOD must be 'source' or 'artifact', found '${DBUS_BROKER_INSTALL_METHOD:-}'"
      ;;
  esac
}

verify_build_manifest() {
  case "${DBUS_BROKER_INSTALL_METHOD:-}" in
    source)
      grep -F "Meson args:" "$DBUS_BROKER_BUILD_VERIFICATION_PATH" >/dev/null || {
        die "build verification file is missing the Meson argument section"
      }
      ;;
    artifact)
      grep -F "Artifact SHA256: $(normalize_sha256_value "$DBUS_BROKER_TARBALL_SHA")" "$DBUS_BROKER_BUILD_VERIFICATION_PATH" >/dev/null || {
        die "artifact verification file is missing the expected tarball sha"
      }
      grep -F "## dbus-broker" "$DBUS_BROKER_ARTIFACT_RELEASE_VERIFICATION_PATH" >/dev/null || {
        die "release verification file is missing the expected dbus-broker marker"
      }
      ;;
    *)
      die "DBUS_BROKER_INSTALL_METHOD must be 'source' or 'artifact', found '${DBUS_BROKER_INSTALL_METHOD:-}'"
      ;;
  esac
}

verify_unit_content() {
  grep -F "ExecStart=${DBUS_BROKER_INSTALL_BIN_DIR}/dbus-broker-launch --scope system" "$DBUS_BROKER_SYSTEM_UNIT_PATH" >/dev/null || {
    die "system unit does not point at managed dbus-broker-launch --scope system"
  }
  grep -F "ExecStart=${DBUS_BROKER_INSTALL_BIN_DIR}/dbus-broker-launch --scope user" "$DBUS_BROKER_USER_UNIT_PATH" >/dev/null || {
    die "user unit does not point at managed dbus-broker-launch --scope user"
  }
  systemd-analyze verify "$DBUS_BROKER_SYSTEM_UNIT_PATH" "$DBUS_BROKER_USER_UNIT_PATH" >/dev/null
}

verify_session_service_alias() {
  local alias_path="$1"
  local source_path="$2"
  [[ -f "$source_path" ]] || return 0
  [[ -f "$alias_path" ]] || die "missing D-Bus compatibility service file: $alias_path"
  cmp -s "$alias_path" "$source_path" || {
    die "D-Bus compatibility service file '$alias_path' does not match '$source_path'"
  }
}

verify_session_service_aliases() {
  verify_session_service_alias "$(dbus_service_alias_path "org.freedesktop.Notifications.service")" "/usr/share/dbus-1/services/fr.emersion.mako.service"
  verify_session_service_alias "$(dbus_service_alias_path "org.freedesktop.FileManager1.service")" "/usr/share/dbus-1/services/org.xfce.Thunar.FileManager1.service"
  verify_session_service_alias "$(dbus_service_alias_path "org.freedesktop.thumbnails.Cache1.service")" "/usr/share/dbus-1/services/org.xfce.Tumbler.Cache1.service"
  verify_session_service_alias "$(dbus_service_alias_path "org.freedesktop.thumbnails.Manager1.service")" "/usr/share/dbus-1/services/org.xfce.Tumbler.Manager1.service"
  verify_session_service_alias "$(dbus_service_alias_path "org.freedesktop.thumbnails.Thumbnailer1.service")" "/usr/share/dbus-1/services/org.xfce.Tumbler.Thumbnailer1.service"
}

read_proc_exe_path() {
  local pid="$1"
  local exe_path

  exe_path="$(readlink "/proc/$pid/exe" 2>/dev/null || true)"
  if [[ -z "$exe_path" ]]; then
    exe_path="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
  fi

  printf '%s\n' "$exe_path"
}

normalize_runtime_exe_path() {
  local exe_path="$1"
  printf '%s\n' "${exe_path% (deleted)}"
}

verify_system_runtime() {
  local fragment_path main_pid exe_path normalized_exe_path
  fragment_path="$(systemctl show -p FragmentPath --value dbus.service)"
  [[ "$fragment_path" == "$DBUS_BROKER_SYSTEM_UNIT_PATH" ]] || {
    die "system dbus.service fragment mismatch: expected '$DBUS_BROKER_SYSTEM_UNIT_PATH', got '${fragment_path:-unknown}'"
  }

  main_pid="$(systemctl show -p MainPID --value dbus.service)"
  [[ "$main_pid" =~ ^[0-9]+$ ]] || die "system dbus.service MainPID is not numeric: '$main_pid'"
  ((main_pid > 1)) || die "system dbus.service is not running (MainPID=$main_pid)"

  exe_path="$(read_proc_exe_path "$main_pid")"
  normalized_exe_path="$(normalize_runtime_exe_path "$exe_path")"
  case "$normalized_exe_path" in
    "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker-launch")
      pgrep -P "$main_pid" -x dbus-broker >/dev/null 2>&1 || die "dbus-broker worker process is not attached under dbus-broker-launch"
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
  local user_fragment user_main_pid user_exe normalized_user_exe
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
    user_exe="$(read_proc_exe_path "$user_main_pid")"
    normalized_user_exe="$(normalize_runtime_exe_path "$user_exe")"
    case "$normalized_user_exe" in
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
  local session_entry="/usr/local/bin/labwc-session-start"
  local session_desktop="/usr/share/wayland-sessions/labwc.desktop"
  local session_autostart="${DBUS_BROKER_TARGET_HOME}/.config/labwc/autostart"
  if [[ -f "$session_wrapper" ]]; then
    grep -F "LABWC_UPDATE_ACTIVATION_ENV=0" "$session_wrapper" >/dev/null || {
      die "labwc-session wrapper lost the managed dbus activation contract"
    }
    [[ -x "$session_entry" ]] || die "missing executable broker-aware labwc session entrypoint: $session_entry"
    grep -F 'DBUS_SESSION_BUS_ADDRESS=' "$session_entry" >/dev/null || {
      die "labwc session entrypoint lost broker-backed user-bus export"
    }
    grep -F 'refusing to fall back to dbus-run-session' "$session_entry" >/dev/null || {
      die "labwc session entrypoint lost the broker-only no-fallback contract"
    }
    [[ -f "$session_desktop" ]] || die "missing labwc desktop session file: $session_desktop"
    awk -F= '
      $1 == "Exec" {
        if ($2 == "/usr/local/bin/labwc-session-start") {
          found = 1
        }
      }
      END {
        exit(found ? 0 : 1)
      }
    ' "$session_desktop" >/dev/null || {
      die "labwc desktop session no longer uses the broker-aware session entrypoint"
    }
    [[ -f "$session_autostart" ]] || {
      die "missing labwc autostart script for managed dbus activation handoff: $session_autostart"
    }
    grep -F "dbus-update-activation-environment --systemd" "$session_autostart" >/dev/null || {
      die "labwc autostart lost dbus/systemd activation-environment handoff"
    }
    grep -F "dbus-update-activation-environment \$dbus_vars" "$session_autostart" >/dev/null || {
      die "labwc autostart lost plain D-Bus activation-environment handoff"
    }
  fi
}

verify_install() {
  verify_packages
  verify_paths
  verify_launcher_binary_contract
  verify_provenance_file
  verify_build_manifest
  verify_unit_content
  verify_session_service_aliases
  verify_system_runtime
  verify_user_runtime
  verify_labwc_session_compatibility
  log_info "verification completed"
}
