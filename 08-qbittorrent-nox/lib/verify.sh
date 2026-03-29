#!/usr/bin/env bash

assert_path_state() {
  local path="$1"
  local expected_user="$2"
  local expected_group="$3"
  local expected_mode="$4"
  local actual_mode actual_user actual_group

  actual_mode="$(stat -c '%a' "$path")"
  actual_user="$(stat -c '%U' "$path")"
  actual_group="$(stat -c '%G' "$path")"

  [[ "$actual_mode" == "$expected_mode" ]] || die "unexpected mode on '$path': expected $expected_mode, found $actual_mode"
  [[ "$actual_user" == "$expected_user" ]] || die "unexpected owner on '$path': expected $expected_user, found $actual_user"
  [[ "$actual_group" == "$expected_group" ]] || die "unexpected group on '$path': expected $expected_group, found $actual_group"
}

verify_packages() {
  local pkg
  for pkg in "${QBT_PACKAGES[@]}"; do
    package_is_installed "$pkg" || die "package '$pkg' is not installed"
  done
}

verify_detection_state() {
  [[ -n "${QBT_TARGET_USER:-}" ]] || die "QBT_TARGET_USER is empty; run the detect phase"
  [[ -n "${QBT_TARGET_HOME:-}" ]] || die "QBT_TARGET_HOME is empty; run the detect phase"
  [[ -n "${QBT_TORRENTS_ROOT_SOURCE:-}" ]] || die "QBT_TORRENTS_ROOT_SOURCE is empty; run the detect phase"
  [[ -n "${QBT_TORRENTS_COMPLETE_SOURCE:-}" ]] || die "QBT_TORRENTS_COMPLETE_SOURCE is empty; run the detect phase"
  [[ -n "${QBT_TORRENTS_TEMP_SOURCE:-}" ]] || die "QBT_TORRENTS_TEMP_SOURCE is empty; run the detect phase"
}

verify_mounts() {
  ensure_torrent_mounts_present
  [[ "$(findmnt -rn -M "$QBT_TORRENTS_ROOT" -o SOURCE)" == "$QBT_TORRENTS_ROOT_SOURCE" ]] || die "torrent root mount source drifted from detected state"
  [[ "$(findmnt -rn -M "$QBT_TORRENTS_COMPLETE" -o SOURCE)" == "$QBT_TORRENTS_COMPLETE_SOURCE" ]] || die "torrent complete mount source drifted from detected state"
  [[ "$(findmnt -rn -M "$QBT_TORRENTS_TEMP" -o SOURCE)" == "$QBT_TORRENTS_TEMP_SOURCE" ]] || die "torrent temp mount source drifted from detected state"
}

verify_service_account() {
  local home shell expected_shell primary_group
  getent group "$QBT_SERVICE_GROUP" >/dev/null 2>&1 || die "missing group '$QBT_SERVICE_GROUP'"
  id "$QBT_SERVICE_USER" >/dev/null 2>&1 || die "missing user '$QBT_SERVICE_USER'"

  home="$(getent passwd "$QBT_SERVICE_USER" | awk -F: '{print $6}')"
  shell="$(getent passwd "$QBT_SERVICE_USER" | awk -F: '{print $7}')"
  expected_shell="$(readlink -f "$(torrent_nologin_shell)")"
  primary_group="$(id -gn "$QBT_SERVICE_USER")"

  [[ "$home" == "/nonexistent" ]] || die "torrent service account home is '$home', expected '/nonexistent'"
  [[ "$(readlink -f "$shell")" == "$expected_shell" ]] || die "torrent service account shell is '$shell', expected nologin"
  [[ "$primary_group" == "$QBT_SERVICE_GROUP" ]] || die "torrent service account primary group is '$primary_group', expected '$QBT_SERVICE_GROUP'"
  id -nG "$QBT_TARGET_USER" | tr ' ' '\n' | grep -Fx "$QBT_SERVICE_GROUP" >/dev/null 2>&1 || die "target user '$QBT_TARGET_USER' is not a member of '$QBT_SERVICE_GROUP'"
}

verify_runtime_paths() {
  require_directory "$QBT_RUNTIME_ROOT"
  require_directory "$QBT_CONFIG_DIR"
  require_directory "$QBT_DATA_DIR"
  require_file "$QBT_CONFIG_PATH"
  require_file "$QBT_MOUNT_CHECK_PATH"
  require_file "$QBT_SERVICE_PATH"
  require_file "$QBT_APPARMOR_PROFILE_PATH"

  assert_path_state "$QBT_RUNTIME_ROOT" "$QBT_SERVICE_USER" "$QBT_SERVICE_GROUP" "750"
  assert_path_state "$QBT_CONFIG_DIR" "$QBT_SERVICE_USER" "$QBT_SERVICE_GROUP" "750"
  assert_path_state "$QBT_DATA_DIR" "$QBT_SERVICE_USER" "$QBT_SERVICE_GROUP" "750"
  assert_path_state "$QBT_CONFIG_PATH" "$QBT_SERVICE_USER" "$QBT_SERVICE_GROUP" "640"
  assert_path_state "$QBT_MOUNT_CHECK_PATH" "root" "root" "755"
  assert_path_state "$QBT_SERVICE_PATH" "root" "root" "644"
  assert_path_state "$QBT_APPARMOR_PROFILE_PATH" "root" "root" "644"

  assert_path_state "$QBT_TORRENTS_ROOT" "$QBT_SERVICE_USER" "$QBT_SERVICE_GROUP" "2770"
  assert_path_state "$QBT_TORRENTS_COMPLETE" "$QBT_SERVICE_USER" "$QBT_SERVICE_GROUP" "2770"
  assert_path_state "$QBT_TORRENTS_TEMP" "$QBT_SERVICE_USER" "$QBT_SERVICE_GROUP" "2770"
}

verify_config_file() {
  grep -F "Session\\DefaultSavePath=${QBT_TORRENTS_COMPLETE}" "$QBT_CONFIG_PATH" >/dev/null || die "qBittorrent config is missing the managed complete path"
  grep -F "Session\\TempPath=${QBT_TORRENTS_TEMP}" "$QBT_CONFIG_PATH" >/dev/null || die "qBittorrent config is missing the managed temp path"
  grep -F "Session\\Port=${QBT_TORRENT_LISTEN_PORT}" "$QBT_CONFIG_PATH" >/dev/null || die "qBittorrent config is missing the managed torrent listen port"
  grep -F "WebUI\\Address=${QBT_WEBUI_ADDRESS}" "$QBT_CONFIG_PATH" >/dev/null || die "qBittorrent config is missing the managed WebUI bind address"
  grep -F "WebUI\\Port=${QBT_WEBUI_PORT}" "$QBT_CONFIG_PATH" >/dev/null || die "qBittorrent config is missing the managed WebUI port"
  grep -F "WebUI\\Username=${QBT_WEBUI_USERNAME}" "$QBT_CONFIG_PATH" >/dev/null || die "qBittorrent config is missing the managed WebUI username"
  grep -E '^WebUI\\Password_PBKDF2=@ByteArray\(.+\)$' "$QBT_CONFIG_PATH" >/dev/null || die "qBittorrent config does not contain a PBKDF2 WebUI password hash"
  grep -F 'WebUI\LocalHostAuth=false' "$QBT_CONFIG_PATH" >/dev/null || die "qBittorrent config must keep localhost auth disabled in favor of password auth"
  grep -F 'WebUI\AuthSubnetWhitelistEnabled=false' "$QBT_CONFIG_PATH" >/dev/null || die "qBittorrent config must keep auth subnet bypass disabled"
  grep -F 'WebUI\HostHeaderValidation=true' "$QBT_CONFIG_PATH" >/dev/null || die "qBittorrent config must keep host header validation enabled"
  grep -F 'Application\FileLoggerEnabled=false' "$QBT_CONFIG_PATH" >/dev/null || die "qBittorrent config must rely on journal logging only"
}

verify_service_unit() {
  grep -F "User=${QBT_SERVICE_USER}" "$QBT_SERVICE_PATH" >/dev/null || die "systemd unit is missing the torrent service user"
  grep -F "Group=${QBT_SERVICE_GROUP}" "$QBT_SERVICE_PATH" >/dev/null || die "systemd unit is missing the torrent service group"
  grep -F "ExecStartPre=${QBT_MOUNT_CHECK_PATH}" "$QBT_SERVICE_PATH" >/dev/null || die "systemd unit is missing the exact mount guard"
  grep -F "ConditionPathIsMountPoint=${QBT_TORRENTS_ROOT}" "$QBT_SERVICE_PATH" >/dev/null || die "systemd unit is missing the torrent root mount condition"
  grep -F "ConditionPathIsMountPoint=${QBT_TORRENTS_COMPLETE}" "$QBT_SERVICE_PATH" >/dev/null || die "systemd unit is missing the complete mount condition"
  grep -F "ConditionPathIsMountPoint=${QBT_TORRENTS_TEMP}" "$QBT_SERVICE_PATH" >/dev/null || die "systemd unit is missing the temp mount condition"
  grep -F 'ProtectSystem=strict' "$QBT_SERVICE_PATH" >/dev/null || die "systemd unit is missing ProtectSystem=strict"
  grep -F 'ProtectHome=yes' "$QBT_SERVICE_PATH" >/dev/null || die "systemd unit is missing ProtectHome=yes"
  grep -F 'NoNewPrivileges=yes' "$QBT_SERVICE_PATH" >/dev/null || die "systemd unit is missing NoNewPrivileges=yes"
  grep -F 'PrivateDevices=yes' "$QBT_SERVICE_PATH" >/dev/null || die "systemd unit is missing PrivateDevices=yes"
  grep -F 'PrivateTmp=yes' "$QBT_SERVICE_PATH" >/dev/null || die "systemd unit is missing PrivateTmp=yes"
  grep -F 'CapabilityBoundingSet=' "$QBT_SERVICE_PATH" >/dev/null || die "systemd unit is missing an empty CapabilityBoundingSet"
  grep -F 'AmbientCapabilities=' "$QBT_SERVICE_PATH" >/dev/null || die "systemd unit is missing empty AmbientCapabilities"
  grep -F 'RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK' "$QBT_SERVICE_PATH" >/dev/null || die "systemd unit is missing the managed address-family restriction"
  grep -F 'SystemCallFilter=@system-service' "$QBT_SERVICE_PATH" >/dev/null || die "systemd unit is missing the base system-call allowlist"
  grep -F 'SystemCallFilter=~@privileged @mount @module @raw-io @reboot @swap' "$QBT_SERVICE_PATH" >/dev/null || die "systemd unit is missing the system-call denylist"

  systemctl is-enabled "$QBT_SERVICE_NAME" >/dev/null 2>&1 || die "$QBT_SERVICE_NAME is not enabled"
  systemctl is-active "$QBT_SERVICE_NAME" >/dev/null 2>&1 || die "$QBT_SERVICE_NAME is not active"

  if command -v systemd-analyze >/dev/null 2>&1; then
    run_cmd systemd-analyze verify "$QBT_SERVICE_PATH"
  fi
}

verify_apparmor_profile() {
  grep -F "${QBT_RUNTIME_ROOT}/** rwk," "$QBT_APPARMOR_PROFILE_PATH" >/dev/null || die "AppArmor profile is missing runtime write access"
  grep -F "${QBT_TORRENTS_COMPLETE}/** rwk," "$QBT_APPARMOR_PROFILE_PATH" >/dev/null || die "AppArmor profile is missing complete-directory write access"
  grep -F "${QBT_TORRENTS_TEMP}/** rwk," "$QBT_APPARMOR_PROFILE_PATH" >/dev/null || die "AppArmor profile is missing temp-directory write access"
  grep -F 'network inet stream,' "$QBT_APPARMOR_PROFILE_PATH" >/dev/null || die "AppArmor profile is missing IPv4 TCP access"
  grep -F 'network inet6 stream,' "$QBT_APPARMOR_PROFILE_PATH" >/dev/null || die "AppArmor profile is missing IPv6 TCP access"
  grep -F '/usr/bin/qbittorrent-nox mr,' "$QBT_APPARMOR_PROFILE_PATH" >/dev/null || die "AppArmor profile is missing the qbittorrent binary rule"

  if [[ -r /sys/kernel/security/apparmor/profiles ]]; then
    grep -F '/usr/bin/qbittorrent-nox (enforce)' /sys/kernel/security/apparmor/profiles >/dev/null || die "qBittorrent AppArmor profile is not loaded in enforce mode"
  fi
}

verify_install() {
  verify_packages
  verify_detection_state
  verify_mounts
  verify_service_account
  verify_runtime_paths
  verify_config_file
  verify_service_unit
  verify_apparmor_profile
  log_info "verification completed"
}
