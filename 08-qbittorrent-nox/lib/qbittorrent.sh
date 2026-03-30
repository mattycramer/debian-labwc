#!/usr/bin/env bash

readonly QBT_SERVICE_USER="torrent"
readonly QBT_SERVICE_GROUP="torrent"
readonly QBT_RUNTIME_ROOT="/var/lib/qbittorrent-nox"
readonly QBT_CONFIG_DIR="${QBT_RUNTIME_ROOT}/.config/qBittorrent"
readonly QBT_CONFIG_PATH="${QBT_CONFIG_DIR}/qBittorrent.conf"
readonly QBT_DATA_DIR="${QBT_RUNTIME_ROOT}/.local/share/data/qBittorrent"
readonly QBT_SERVICE_NAME="qbittorrent-nox.service"
readonly QBT_SERVICE_PATH="/etc/systemd/system/${QBT_SERVICE_NAME}"
readonly QBT_APPARMOR_PROFILE_NAME="usr.bin.qbittorrent-nox"
readonly QBT_APPARMOR_PROFILE_PATH="/etc/apparmor.d/${QBT_APPARMOR_PROFILE_NAME}"
readonly QBT_HELPER_DIR="/usr/local/libexec/labwc-qbittorrent"
readonly QBT_MOUNT_CHECK_PATH="${QBT_HELPER_DIR}/require-mounts.sh"
readonly QBT_TORRENTS_ROOT="/data/mnt/g-drive/torrents"
readonly QBT_TORRENTS_COMPLETE="${QBT_TORRENTS_ROOT}/complete"
readonly QBT_TORRENTS_TEMP="${QBT_TORRENTS_ROOT}/temp"
readonly QBT_TORRENTS_ROOT_MOUNT_UNIT="data-mnt-g\\x2ddrive-torrents.mount"
readonly QBT_TORRENTS_COMPLETE_MOUNT_UNIT="data-mnt-g\\x2ddrive-torrents-complete.mount"
readonly QBT_TORRENTS_TEMP_MOUNT_UNIT="data-mnt-g\\x2ddrive-torrents-temp.mount"

torrent_nologin_shell() {
  command -v nologin
}

write_root_file() {
  local destination="$1"
  local mode="$2"
  local content="$3"
  run_cmd install -D -m "$mode" /dev/null "$destination"
  printf '%s\n' "$content" >"$destination"
  run_cmd chmod "$mode" "$destination"
}

write_torrent_file() {
  local destination="$1"
  local mode="$2"
  local content="$3"
  run_cmd install -D -m "$mode" -o "$QBT_SERVICE_USER" -g "$QBT_SERVICE_GROUP" /dev/null "$destination"
  printf '%s\n' "$content" >"$destination"
  run_cmd chown "$QBT_SERVICE_USER:$QBT_SERVICE_GROUP" "$destination"
  run_cmd chmod "$mode" "$destination"
}

validate_env_settings() {
  require_loopback_bind_address "QBT_WEBUI_ADDRESS" "${QBT_WEBUI_ADDRESS:-}"
  require_port_number "QBT_WEBUI_PORT" "${QBT_WEBUI_PORT:-}"
  require_safe_token "QBT_WEBUI_USERNAME" "${QBT_WEBUI_USERNAME:-}"
  require_port_number "QBT_TORRENT_LISTEN_PORT" "${QBT_TORRENT_LISTEN_PORT:-}"
  require_positive_integer "QBT_MAX_ACTIVE_DOWNLOADS" "${QBT_MAX_ACTIVE_DOWNLOADS:-}"
  require_positive_integer "QBT_MAX_ACTIVE_UPLOADS" "${QBT_MAX_ACTIVE_UPLOADS:-}"
  require_positive_integer "QBT_MAX_ACTIVE_TORRENTS" "${QBT_MAX_ACTIVE_TORRENTS:-}"
  require_positive_integer "QBT_MAX_CONNECTIONS" "${QBT_MAX_CONNECTIONS:-}"
  require_positive_integer "QBT_MAX_CONNECTIONS_PER_TORRENT" "${QBT_MAX_CONNECTIONS_PER_TORRENT:-}"
  require_positive_integer "QBT_MAX_UPLOADS" "${QBT_MAX_UPLOADS:-}"
  require_positive_integer "QBT_MAX_UPLOADS_PER_TORRENT" "${QBT_MAX_UPLOADS_PER_TORRENT:-}"
  require_decimal_number "QBT_GLOBAL_MAX_RATIO" "${QBT_GLOBAL_MAX_RATIO:-}"
  require_integer_or_minus_one "QBT_GLOBAL_MAX_SEEDING_MINUTES" "${QBT_GLOBAL_MAX_SEEDING_MINUTES:-}"
}

ensure_torrent_group() {
  local gid
  if getent group "$QBT_SERVICE_GROUP" >/dev/null 2>&1; then
    gid="$(getent group "$QBT_SERVICE_GROUP" | awk -F: '{print $3}')"
    [[ "$gid" =~ ^[0-9]+$ ]] || die "could not parse GID for '$QBT_SERVICE_GROUP'"
    ((gid < 1000)) || die "existing group '$QBT_SERVICE_GROUP' is not a system group (gid=$gid)"
    return 0
  fi

  run_cmd groupadd --system "$QBT_SERVICE_GROUP"
}

ensure_torrent_user_locked() {
  local shadow_hash
  shadow_hash="$(getent shadow "$QBT_SERVICE_USER" | awk -F: '{print $2}')"
  case "$shadow_hash" in
    '!'*|'*')
      return 0
      ;;
    *)
      run_cmd usermod --lock "$QBT_SERVICE_USER"
      ;;
  esac
}

verify_existing_torrent_user() {
  local uid gid home shell primary_group expected_shell
  uid="$(id -u "$QBT_SERVICE_USER")"
  gid="$(id -g "$QBT_SERVICE_USER")"
  home="$(getent passwd "$QBT_SERVICE_USER" | awk -F: '{print $6}')"
  shell="$(getent passwd "$QBT_SERVICE_USER" | awk -F: '{print $7}')"
  primary_group="$(id -gn "$QBT_SERVICE_USER")"
  expected_shell="$(readlink -f "$(torrent_nologin_shell)")"

  [[ "$uid" =~ ^[0-9]+$ ]] || die "could not parse UID for '$QBT_SERVICE_USER'"
  [[ "$gid" =~ ^[0-9]+$ ]] || die "could not parse GID for '$QBT_SERVICE_USER'"
  ((uid < 1000)) || die "existing user '$QBT_SERVICE_USER' is not a system user (uid=$uid)"
  ((gid < 1000)) || die "existing user '$QBT_SERVICE_USER' does not use a system group (gid=$gid)"
  [[ "$primary_group" == "$QBT_SERVICE_GROUP" ]] || die "existing user '$QBT_SERVICE_USER' does not have primary group '$QBT_SERVICE_GROUP'"
  [[ "$home" == "/nonexistent" ]] || die "existing user '$QBT_SERVICE_USER' does not use the required home '/nonexistent'"
  [[ "$(readlink -f "$shell")" == "$expected_shell" ]] || die "existing user '$QBT_SERVICE_USER' does not use the required nologin shell"
}

ensure_torrent_service_account() {
  ensure_torrent_group

  if id "$QBT_SERVICE_USER" >/dev/null 2>&1; then
    verify_existing_torrent_user
    ensure_torrent_user_locked
    return 0
  fi

  run_cmd useradd \
    --system \
    --gid "$QBT_SERVICE_GROUP" \
    --home-dir /nonexistent \
    --no-create-home \
    --shell "$(torrent_nologin_shell)" \
    "$QBT_SERVICE_USER"
  ensure_torrent_user_locked
}

ensure_target_user_membership() {
  [[ -n "${QBT_TARGET_USER:-}" ]] || die "QBT_TARGET_USER is empty; run the detect phase first"
  [[ "$QBT_TARGET_USER" != "root" ]] || die "refusing to manage torrent group membership for root"

  if id -nG "$QBT_TARGET_USER" | tr ' ' '\n' | grep -Fx "$QBT_SERVICE_GROUP" >/dev/null 2>&1; then
    return 0
  fi

  run_cmd usermod -a -G "$QBT_SERVICE_GROUP" "$QBT_TARGET_USER"
}

ensure_torrent_mounts_present() {
  require_exact_mountpoint "$QBT_TORRENTS_ROOT"
  require_exact_mountpoint "$QBT_TORRENTS_COMPLETE"
  require_exact_mountpoint "$QBT_TORRENTS_TEMP"
}

enforce_torrent_mount_ownership() {
  local path
  ensure_torrent_mounts_present

  for path in "$QBT_TORRENTS_ROOT" "$QBT_TORRENTS_COMPLETE" "$QBT_TORRENTS_TEMP"; do
    run_cmd chown "$QBT_SERVICE_USER:$QBT_SERVICE_GROUP" "$path"
    run_cmd chmod 2770 "$path"
  done
}

ensure_runtime_directories() {
  run_cmd install -d -m 0700 -o "$QBT_SERVICE_USER" -g "$QBT_SERVICE_GROUP" \
    "$QBT_RUNTIME_ROOT" \
    "$QBT_CONFIG_DIR" \
    "$QBT_DATA_DIR"
}

normalize_webui_password_hash() {
  local value="$1"
  case "$value" in
    @ByteArray\(*\))
      printf '%s' "$value"
      ;;
    *:*)
      printf '@ByteArray(%s)' "$value"
      ;;
    *)
      die "QBT_WEBUI_PASSWORD_PBKDF2 must be in 'salt:key' or '@ByteArray(salt:key)' form"
      ;;
  esac
}

current_webui_password_hash() {
  if [[ ! -f "$QBT_CONFIG_PATH" ]]; then
    return 0
  fi

  awk -F= '/^WebUI\\Password_PBKDF2=/{sub(/^[^=]*=/, ""); print; exit}' "$QBT_CONFIG_PATH"
}

generate_webui_password_hash() {
  local password="$1"
  QBT_PASSWORD_RAW="$password" python3 - <<'PY'
import base64
import hashlib
import os

password = os.environ["QBT_PASSWORD_RAW"].encode()
if not password:
    raise SystemExit("refusing to generate an empty qBittorrent WebUI password hash")

salt = os.urandom(16)
key = hashlib.pbkdf2_hmac("sha512", password, salt, 100000)
print(f"@ByteArray({base64.b64encode(salt).decode()}:{base64.b64encode(key).decode()})")
PY
}

prompt_for_webui_password() {
  local first second
  [[ -t 0 ]] || die "QBT_WEBUI_PASSWORD is empty and no interactive terminal is available for prompting"

  while true; do
    IFS= read -r -s -p "Enter qBittorrent WebUI password for ${QBT_WEBUI_USERNAME}: " first
    printf '\n'
    [[ -n "$first" ]] || {
      log_warn "empty passwords are not allowed"
      continue
    }

    IFS= read -r -s -p "Re-enter qBittorrent WebUI password: " second
    printf '\n'

    [[ "$first" == "$second" ]] || {
      log_warn "passwords did not match"
      continue
    }

    printf '%s' "$first"
    return 0
  done
}

resolve_webui_password_hash() {
  local existing_hash raw_password

  if [[ -n "${QBT_WEBUI_PASSWORD_PBKDF2:-}" ]]; then
    QBT_WEBUI_PASSWORD_HASH="$(normalize_webui_password_hash "$QBT_WEBUI_PASSWORD_PBKDF2")"
    return 0
  fi

  if [[ -n "${QBT_WEBUI_PASSWORD:-}" ]]; then
    QBT_WEBUI_PASSWORD_HASH="$(generate_webui_password_hash "$QBT_WEBUI_PASSWORD")"
    return 0
  fi

  existing_hash="$(current_webui_password_hash || true)"
  if [[ -n "$existing_hash" ]]; then
    QBT_WEBUI_PASSWORD_HASH="$(normalize_webui_password_hash "$existing_hash")"
    return 0
  fi

  raw_password="$(prompt_for_webui_password)"
  QBT_WEBUI_PASSWORD_HASH="$(generate_webui_password_hash "$raw_password")"
}

render_mount_check_script() {
  local content
  content="$(cat <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

required_mounts=(
  "/data/mnt/g-drive/torrents"
  "/data/mnt/g-drive/torrents/complete"
  "/data/mnt/g-drive/torrents/temp"
)

for path in "${required_mounts[@]}"; do
  if [[ "$(findmnt -rn -M "$path" -o TARGET 2>/dev/null || true)" != "$path" ]]; then
    printf 'required qBittorrent mount is not present: %s\n' "$path" >&2
    exit 1
  fi
done
EOF
)"

  write_root_file "$QBT_MOUNT_CHECK_PATH" 0755 "$content"
}

render_qbittorrent_config() {
  local content
  resolve_webui_password_hash

  content="$(cat <<EOF
[LegalNotice]
Accepted=true

[BitTorrent]
Session\\DefaultSavePath=${QBT_TORRENTS_COMPLETE}
Session\\TempPath=${QBT_TORRENTS_TEMP}
Session\\TempPathEnabled=true
Session\\Port=${QBT_TORRENT_LISTEN_PORT}
Session\\Encryption=1
Session\\DHT=true
Session\\PeX=true
Session\\LSD=true
Session\\uTP=true
Session\\uTPRateLimited=true
Session\\GlobalMaxRatio=${QBT_GLOBAL_MAX_RATIO}
Session\\GlobalMaxSeedingMinutes=${QBT_GLOBAL_MAX_SEEDING_MINUTES}
Session\\MaxActiveDownloads=${QBT_MAX_ACTIVE_DOWNLOADS}
Session\\MaxActiveUploads=${QBT_MAX_ACTIVE_UPLOADS}
Session\\MaxActiveTorrents=${QBT_MAX_ACTIVE_TORRENTS}
Session\\MaxConnections=${QBT_MAX_CONNECTIONS}
Session\\MaxConnectionsPerTorrent=${QBT_MAX_CONNECTIONS_PER_TORRENT}
Session\\MaxUploads=${QBT_MAX_UPLOADS}
Session\\MaxUploadsPerTorrent=${QBT_MAX_UPLOADS_PER_TORRENT}
Session\\AnonymousMode=false
Session\\AddTorrentPaused=false
Session\\CreateTorrentSubfolder=true
Session\\DisableAutoTMMByDefault=false
Session\\QueueingSystemEnabled=true
Session\\SlowTorrentsDownloadRate=2
Session\\SlowTorrentsUploadRate=2
Session\\SlowTorrentsInactivityTimer=60
Session\\FilePoolSize=500
Session\\CheckingMemUsage=32
Session\\DiskCacheSize=-1
Session\\DiskCacheTTL=60
Session\\UseOSCache=true
Session\\CoalesceReadWrite=false
Session\\PieceExtentAffinity=false
Session\\SendBufferWatermark=500
Session\\SendBufferLowWatermark=10
Session\\SendBufferWatermarkFactor=50
Session\\SaveResumeDataInterval=60
Session\\OutgoingPortsMin=0
Session\\OutgoingPortsMax=0
Session\\IgnoreLimitsOnLAN=true
Session\\IncludeOverheadInLimits=false
Session\\AnnounceToAllTrackers=false
Session\\AnnounceToAllTiers=true
Session\\SeedChokingAlgorithm=FastestUpload
Session\\SuperSeedingEnabled=false
Session\\BandwidthSchedulerEnabled=false

[Preferences]
WebUI\\Address=${QBT_WEBUI_ADDRESS}
WebUI\\Port=${QBT_WEBUI_PORT}
WebUI\\Username=${QBT_WEBUI_USERNAME}
WebUI\\Password_PBKDF2=${QBT_WEBUI_PASSWORD_HASH}
WebUI\\LocalHostAuth=false
WebUI\\AuthSubnetWhitelistEnabled=false
WebUI\\UseUPnP=false
WebUI\\HTTPS\\Enabled=false
WebUI\\CSRFProtection=true
WebUI\\ClickjackingProtection=true
WebUI\\SecureCookie=true
WebUI\\HostHeaderValidation=true
Downloads\\SavePath=${QBT_TORRENTS_COMPLETE}
Downloads\\TempPath=${QBT_TORRENTS_TEMP}
Downloads\\TempPathEnabled=true
Downloads\\PreAllocation=false
Downloads\\UseIncompleteExtension=true
Downloads\\ScanDirs=@Variant()
Downloads\\StartInPause=false
Downloads\\CreateSubfolder=true
Connection\\PortRangeMin=${QBT_TORRENT_LISTEN_PORT}
Connection\\UPnP=false
Connection\\GlobalDLLimit=0
Connection\\GlobalULLimit=0
Connection\\GlobalDLLimitAlt=0
Connection\\GlobalULLimitAlt=0
General\\Locale=en
General\\UseRandomPort=false
RSS\\AutoDownloader\\EnableProcessing=false
RSS\\RefreshInterval=30
RSS\\MaxArticlesPerFeed=50
Application\\FileLoggerEnabled=false
EOF
)"

  write_torrent_file "$QBT_CONFIG_PATH" 0600 "$content"
}

render_systemd_service() {
  local content
  content="$(cat <<EOF
[Unit]
Description=Hardened qBittorrent-nox headless torrent client
Documentation=man:qbittorrent-nox(1)
Wants=network-online.target
After=network-online.target nss-lookup.target local-fs.target
BindsTo=${QBT_TORRENTS_ROOT_MOUNT_UNIT} ${QBT_TORRENTS_COMPLETE_MOUNT_UNIT} ${QBT_TORRENTS_TEMP_MOUNT_UNIT}
After=${QBT_TORRENTS_ROOT_MOUNT_UNIT} ${QBT_TORRENTS_COMPLETE_MOUNT_UNIT} ${QBT_TORRENTS_TEMP_MOUNT_UNIT}
RequiresMountsFor=${QBT_TORRENTS_ROOT} ${QBT_TORRENTS_COMPLETE} ${QBT_TORRENTS_TEMP}
ConditionPathIsMountPoint=${QBT_TORRENTS_ROOT}
ConditionPathIsMountPoint=${QBT_TORRENTS_COMPLETE}
ConditionPathIsMountPoint=${QBT_TORRENTS_TEMP}

[Service]
Type=exec
User=${QBT_SERVICE_USER}
Group=${QBT_SERVICE_GROUP}
UMask=0007
WorkingDirectory=${QBT_RUNTIME_ROOT}
StateDirectory=qbittorrent-nox
StateDirectoryMode=0700
Environment=HOME=${QBT_RUNTIME_ROOT}
ExecStartPre=${QBT_MOUNT_CHECK_PATH}
ExecStart=/usr/bin/qbittorrent-nox --webui-port=${QBT_WEBUI_PORT}
Restart=on-failure
RestartSec=5s
TimeoutStartSec=30s
TimeoutStopSec=45s
KillMode=mixed
LimitNOFILE=65536
TasksMax=128
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=${QBT_TORRENTS_COMPLETE} ${QBT_TORRENTS_TEMP}
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectHostname=yes
ProtectClock=yes
ProtectProc=invisible
ProcSubset=pid
LockPersonality=yes
MemoryDenyWriteExecute=yes
RemoveIPC=yes
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
CapabilityBoundingSet=
AmbientCapabilities=
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @mount @module @raw-io @reboot @swap
SystemCallErrorNumber=EPERM
KeyringMode=private
StandardOutput=journal
StandardError=journal
SyslogIdentifier=qbittorrent-nox

[Install]
WantedBy=multi-user.target
EOF
)"

  write_root_file "$QBT_SERVICE_PATH" 0644 "$content"
}

render_apparmor_profile() {
  local content
  content="$(cat <<EOF
#include <tunables/global>

/usr/bin/qbittorrent-nox flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  #include <abstractions/nameservice>
  #include <abstractions/openssl>
  #include <abstractions/ssl_certs>
  #include <abstractions/user-tmp>

  network inet dgram,
  network inet stream,
  network inet6 dgram,
  network inet6 stream,
  network netlink raw,
  network unix dgram,
  network unix stream,

  /usr/bin/qbittorrent-nox mr,
  /etc/ld.so.cache r,
  /etc/localtime r,
  /etc/mime.types r,
  /etc/timezone r,
  /proc/net/** r,
  /proc/sys/net/** r,
  /sys/class/net/** r,
  /usr/lib/** mr,
  /usr/libexec/** mr,
  /usr/share/** r,

  ${QBT_RUNTIME_ROOT}/ rw,
  ${QBT_RUNTIME_ROOT}/** rwk,

  ${QBT_TORRENTS_ROOT}/ r,
  ${QBT_TORRENTS_COMPLETE}/ rw,
  ${QBT_TORRENTS_COMPLETE}/** rwk,
  ${QBT_TORRENTS_TEMP}/ rw,
  ${QBT_TORRENTS_TEMP}/** rwk,
}
EOF
)"

  write_root_file "$QBT_APPARMOR_PROFILE_PATH" 0644 "$content"
}

render_all_configs() {
  render_mount_check_script
  render_qbittorrent_config
  render_systemd_service
  render_apparmor_profile
}

require_apparmor_runtime() {
  [[ -r /sys/module/apparmor/parameters/enabled ]] || die "AppArmor kernel support is not available on this host"
  grep -Fxq 'Y' /sys/module/apparmor/parameters/enabled || die "AppArmor is installed but not enabled on this host"
}

load_qbittorrent_apparmor_profile() {
  run_cmd apparmor_parser -r -W "$QBT_APPARMOR_PROFILE_PATH"
}

validate_qbittorrent_service_file() {
  if command -v systemd-analyze >/dev/null 2>&1; then
    run_cmd systemd-analyze verify "$QBT_SERVICE_PATH"
  fi
}

enable_qbittorrent_service() {
  load_qbittorrent_apparmor_profile
  run_cmd systemctl daemon-reload
  validate_qbittorrent_service_file
  run_cmd systemctl enable --now "$QBT_SERVICE_NAME"
}

print_env_redacted() {
  local env_file="$1"
  awk '
    /^QBT_WEBUI_PASSWORD=/ { print "QBT_WEBUI_PASSWORD=\"[redacted]\""; next }
    /^QBT_WEBUI_PASSWORD_PBKDF2=/ { print "QBT_WEBUI_PASSWORD_PBKDF2=\"[redacted]\""; next }
    { print }
  ' "$env_file"
}

remove_qbittorrent_install() {
  if systemctl list-unit-files "$QBT_SERVICE_NAME" >/dev/null 2>&1; then
    run_cmd systemctl disable --now "$QBT_SERVICE_NAME" >/dev/null 2>&1 || true
  fi

  if [[ -f "$QBT_APPARMOR_PROFILE_PATH" ]] && command -v apparmor_parser >/dev/null 2>&1; then
    run_cmd apparmor_parser -R "$QBT_APPARMOR_PROFILE_PATH" >/dev/null 2>&1 || true
  fi

  run_cmd rm -f -- "$QBT_SERVICE_PATH" "$QBT_APPARMOR_PROFILE_PATH" "$QBT_MOUNT_CHECK_PATH"
  run_cmd rmdir --ignore-fail-on-non-empty "$QBT_HELPER_DIR" 2>/dev/null || true
  run_cmd rm -rf -- "$QBT_RUNTIME_ROOT"
  run_cmd systemctl daemon-reload >/dev/null 2>&1 || true
}
