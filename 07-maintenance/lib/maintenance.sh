#!/usr/bin/env bash

readonly MAINTENANCE_RUNTIME_ROOT="/var/lib/labwc-maintenance"
readonly MAINTENANCE_STATE_FILE="${MAINTENANCE_RUNTIME_ROOT}/state.env"
readonly GRUB_BTRFS_CLONE_DIR="/tmp/grub-btrfs"
readonly GRUB_BTRFS_COMMIT_FILE="${MAINTENANCE_RUNTIME_ROOT}/grub-btrfs.commit"
readonly TIMESHIFT_CONFIG_DIR="/etc/timeshift"
readonly TIMESHIFT_CONFIG_PATH="/etc/timeshift/timeshift.json"
readonly TIMESHIFT_DESKTOP_SOURCE_PATH="/usr/share/applications/timeshift-gtk.desktop"
readonly TIMESHIFT_DESKTOP_OVERRIDE_DIR="/usr/local/share/applications"
readonly TIMESHIFT_DESKTOP_OVERRIDE_PATH="/usr/local/share/applications/timeshift-gtk.desktop"
readonly TIMESHIFT_WRAPPER_PATH="/usr/local/bin/timeshift-gtk"
readonly TIMESHIFT_LEGACY_LAUNCHER_PATH="/usr/local/bin/timeshift-launcher"
readonly GRUB_BTRFS_CONFIG_DIR="/etc/default/grub-btrfs"
readonly GRUB_BTRFS_CONFIG_PATH="/etc/default/grub-btrfs/config"
readonly GRUB_BTRFS_SCRIPT_PATH="/etc/grub.d/41_snapshots-btrfs"
readonly GRUB_BTRFS_DAEMON_PATH="/usr/local/bin/grub-btrfsd"
readonly GRUB_BTRFS_SERVICE_PATH="/etc/systemd/system/grub-btrfsd.service"
readonly GRUB_BTRFS_CFG_PATH="/boot/grub/grub-btrfs.cfg"
readonly GRUB_CFG_PATH="/boot/grub/grub.cfg"
readonly GRUB_CUSTOM_CFG_PATH="/boot/grub/custom.cfg"
readonly TIMESHIFT_HOURLY_CRON_NAME="timeshift-hourly"
readonly BTRFSMAINT_CONFIG_PATH="/etc/default/btrfsmaintenance"
readonly BTRFS_SCRUB_DROPIN_DIR="/etc/systemd/system/btrfs-scrub.timer.d"
readonly BTRFS_SCRUB_DROPIN_PATH="/etc/systemd/system/btrfs-scrub.timer.d/zz-labwc.conf"
readonly BTRFS_BALANCE_DROPIN_DIR="/etc/systemd/system/btrfs-balance.timer.d"
readonly BTRFS_BALANCE_DROPIN_PATH="/etc/systemd/system/btrfs-balance.timer.d/zz-labwc.conf"

write_root_file() {
  local destination="$1"
  local mode="$2"
  local content="$3"
  run_cmd install -D -m "$mode" /dev/null "$destination"
  printf '%s' "$content" >"$destination"
  run_cmd chmod "$mode" "$destination"
}

capture_unit_state() {
  local unit_name="$1"
  local key="$2"
  local state
  state="$(systemctl is-enabled "$unit_name" 2>/dev/null || true)"
  printf '%s=%q\n' "$key" "$state" >>"$MAINTENANCE_STATE_FILE"
}

capture_unit_states() {
  run_cmd install -d -m 0755 "$MAINTENANCE_RUNTIME_ROOT"
  : >"$MAINTENANCE_STATE_FILE"
  capture_unit_state "grub-btrfsd.service" "STATE_GRUB_BTRFSD"
  capture_unit_state "fstrim.timer" "STATE_FSTRIM_TIMER"
  capture_unit_state "btrfs-scrub.timer" "STATE_BTRFS_SCRUB_TIMER"
  capture_unit_state "btrfs-balance.timer" "STATE_BTRFS_BALANCE_TIMER"
  capture_unit_state "btrfs-defrag.timer" "STATE_BTRFS_DEFRAG_TIMER"
  capture_unit_state "btrfs-trim.timer" "STATE_BTRFS_TRIM_TIMER"
  capture_unit_state "btrfsmaintenance-refresh.path" "STATE_BTRFS_REFRESH_PATH"
}

restore_unit_state() {
  local unit_name="$1"
  local key="$2"
  local state=""
  [[ -f "$MAINTENANCE_STATE_FILE" ]] || return 0
  # shellcheck disable=SC1090
  source "$MAINTENANCE_STATE_FILE"
  state="${!key:-}"
  case "$state" in
    enabled|enabled-runtime|linked|linked-runtime|alias)
      run_cmd systemctl enable --now "$unit_name" >/dev/null 2>&1 || true
      ;;
    disabled|masked|"")
      run_cmd systemctl disable --now "$unit_name" >/dev/null 2>&1 || true
      ;;
    *)
      :
      ;;
  esac
}

grub_btrfs_snapshot_kernel_parameters() {
  printf '%s\n' "${MAINTENANCE_ROOT_BTRFS_KERNEL_FLAGS}${MAINTENANCE_CURRENT_KERNEL_PARAMETERS:+ ${MAINTENANCE_CURRENT_KERNEL_PARAMETERS}}"
}

clone_grub_btrfs_repo() {
  run_cmd rm -rf -- "$GRUB_BTRFS_CLONE_DIR"
  run_cmd install -d -m 0755 "$MAINTENANCE_RUNTIME_ROOT"
  run_cmd timeout 180 runuser -u "$MAINTENANCE_TARGET_USER" -- env HOME="$MAINTENANCE_TARGET_HOME" \
    git clone "$GRUB_BTRFS_REPO_URL" "$GRUB_BTRFS_CLONE_DIR"
  run_cmd git -C "$GRUB_BTRFS_CLONE_DIR" checkout --detach "$GRUB_BTRFS_REPO_REF"
  printf '%s\n' "$GRUB_BTRFS_REPO_REF" >"$GRUB_BTRFS_COMMIT_FILE"
  run_cmd chmod 0644 "$GRUB_BTRFS_COMMIT_FILE"
  require_file "$GRUB_BTRFS_CLONE_DIR/41_snapshots-btrfs"
  require_file "$GRUB_BTRFS_CLONE_DIR/grub-btrfsd"
}

install_grub_btrfs_files() {
  clone_grub_btrfs_repo
  run_cmd install -D -m 0755 "$GRUB_BTRFS_CLONE_DIR/41_snapshots-btrfs" "$GRUB_BTRFS_SCRIPT_PATH"
  run_cmd install -D -m 0755 "$GRUB_BTRFS_CLONE_DIR/grub-btrfsd" "$GRUB_BTRFS_DAEMON_PATH"
}

render_timeshift_config() {
  local content
  content="$(cat <<EOF
{
  "backup_device_uuid" : "${MAINTENANCE_ROOT_BTRFS_UUID}",
  "parent_device_uuid" : "",
  "do_first_run" : "false",
  "btrfs_mode" : "${TIMESHIFT_BTRFS_MODE}",
  "include_btrfs_home" : "${TIMESHIFT_INCLUDE_BTRFS_HOME}",
  "stop_cron_emails" : "true",
  "schedule_monthly" : "${TIMESHIFT_SCHEDULE_MONTHLY}",
  "schedule_weekly" : "${TIMESHIFT_SCHEDULE_WEEKLY}",
  "schedule_daily" : "${TIMESHIFT_SCHEDULE_DAILY}",
  "schedule_hourly" : "${TIMESHIFT_SCHEDULE_HOURLY}",
  "schedule_boot" : "${TIMESHIFT_SCHEDULE_BOOT}",
  "count_monthly" : "${TIMESHIFT_COUNT_MONTHLY}",
  "count_weekly" : "${TIMESHIFT_COUNT_WEEKLY}",
  "count_daily" : "${TIMESHIFT_COUNT_DAILY}",
  "count_hourly" : "${TIMESHIFT_COUNT_HOURLY}",
  "count_boot" : "${TIMESHIFT_COUNT_BOOT}",
  "snapshot_size" : "0",
  "snapshot_count" : "0",
  "exclude" : [
  ],
  "exclude-apps" : [
  ]
}
EOF
)"
  run_cmd install -d -m 0755 "$TIMESHIFT_CONFIG_DIR"
  write_root_file "$TIMESHIFT_CONFIG_PATH" 0644 "$content"
}

render_timeshift_desktop_override() {
  local content
  content="$(cat <<'EOF'
[Desktop Entry]
Name=Timeshift
Exec=/usr/local/bin/timeshift-gtk
Type=Application
GenericName=System Restore Utility
Terminal=false
Icon=timeshift
Comment=Create and manage system snapshots
X-KDE-StartupNotify=false
Categories=System;
X-GNOME-UsesNotifications=true
Keywords=backup;btrfs;rsync;
EOF
)"
  run_cmd rm -f -- "$TIMESHIFT_DESKTOP_SOURCE_PATH"
  run_cmd install -d -m 0755 "$TIMESHIFT_DESKTOP_OVERRIDE_DIR"
  write_root_file "$TIMESHIFT_DESKTOP_OVERRIDE_PATH" 0644 "$content"
  if command -v update-desktop-database >/dev/null 2>&1; then
    run_cmd update-desktop-database "$TIMESHIFT_DESKTOP_OVERRIDE_DIR"
  fi
}

render_timeshift_wrapper() {
  local content
  content="$(cat <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

if [[ "$(id -u)" -eq 0 ]]; then
  exec /usr/bin/timeshift-gtk "$@"
fi

command -v pkexec >/dev/null 2>&1 || {
  printf '%s\n' 'pkexec is required to launch Timeshift with administrative privileges.' >&2
  exit 1
}

env_args=(
  "DISPLAY=${DISPLAY:-}"
  "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}"
  "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-}"
  "XAUTHORITY=${XAUTHORITY:-}"
  "DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-}"
  "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-}"
  "XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-}"
  "XDG_SESSION_DESKTOP=${XDG_SESSION_DESKTOP:-}"
  "DESKTOP_SESSION=${DESKTOP_SESSION:-}"
)

exec pkexec env "${env_args[@]}" /usr/bin/timeshift-gtk "$@"
EOF
)"
  write_root_file "$TIMESHIFT_WRAPPER_PATH" 0755 "$content"
  run_cmd ln -sfn "$TIMESHIFT_WRAPPER_PATH" "$TIMESHIFT_LEGACY_LAUNCHER_PATH"
}

render_btrfsmaintenance_config() {
  local content
  content="$(cat <<'EOF'
# Managed by labwc 07-maintenance.
# Use btrfsmaintenance's device-deduplicating "auto" mountpoint mode so each
# mounted Btrfs block device is handled once, regardless of how many subvolumes
# are mounted from it.
BTRFS_LOG_OUTPUT="journal"
BTRFS_DEFRAG_PATHS=""
BTRFS_DEFRAG_PERIOD="none"
BTRFS_BALANCE_MOUNTPOINTS="auto"
BTRFS_BALANCE_PERIOD="monthly"
BTRFS_BALANCE_DUSAGE="5 10"
BTRFS_BALANCE_MUSAGE="5"
BTRFS_SCRUB_MOUNTPOINTS="auto"
BTRFS_SCRUB_PERIOD="monthly"
BTRFS_SCRUB_PRIORITY="idle"
BTRFS_SCRUB_READ_ONLY="false"
BTRFS_TRIM_PERIOD="none"
BTRFS_TRIM_MOUNTPOINTS="auto"
BTRFS_ALLOW_CONCURRENCY="false"
EOF
)"
  write_root_file "$BTRFSMAINT_CONFIG_PATH" 0644 "$content"
}

render_grub_btrfs_config() {
  local snapshot_kernel_parameters
  local content
  snapshot_kernel_parameters="$(grub_btrfs_snapshot_kernel_parameters)"
  content="$(cat <<EOF
#!/usr/bin/env bash

# Managed by labwc 07-maintenance.
GRUB_BTRFS_LIMIT="${GRUB_BTRFS_LIMIT}"
GRUB_BTRFS_SHOW_SNAPSHOTS_FOUND="${GRUB_BTRFS_SHOW_SNAPSHOTS_FOUND}"
GRUB_BTRFS_GRUB_DIRNAME="/boot/grub"
GRUB_BTRFS_BOOT_DIRNAME="/boot"
GRUB_BTRFS_GBTRFS_DIRNAME="/boot/grub"
GRUB_BTRFS_GBTRFS_SEARCH_DIRNAME="\${prefix}"
GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS="${snapshot_kernel_parameters}"
GRUB_BTRFS_IGNORE_SPECIFIC_PATH=("@")
GRUB_BTRFS_IGNORE_PREFIX_PATH=("var/lib/docker" "@var/lib/docker" "@/var/lib/docker" "var/lib/containers" "@var/lib/containers" "@/var/lib/containers")
EOF
)"
  run_cmd install -d -m 0755 "$GRUB_BTRFS_CONFIG_DIR"
  write_root_file "$GRUB_BTRFS_CONFIG_PATH" 0644 "$content"
}

render_grub_btrfs_service() {
  local content
  content="$(cat <<'EOF'
[Unit]
Description=Monitor Timeshift Btrfs snapshots and regenerate grub-btrfs.cfg
After=local-fs.target
ConditionPathExists=/etc/grub.d/41_snapshots-btrfs
ConditionPathExists=/etc/default/grub-btrfs/config

[Service]
Type=simple
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EnvironmentFile=/etc/default/grub-btrfs/config
ExecStart=/usr/local/bin/grub-btrfsd --syslog --timeshift-auto
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
)"
  write_root_file "$GRUB_BTRFS_SERVICE_PATH" 0644 "$content"
}

render_btrfs_timer_overrides() {
  local scrub_content balance_content
  scrub_content="$(cat <<EOF
[Timer]
OnCalendar=
OnBootSec=15min
OnUnitActiveSec=${MAINTENANCE_SCRUB_INTERVAL}
AccuracySec=${MAINTENANCE_TIMER_ACCURACY_SEC}
Persistent=true
RandomizedDelaySec=${MAINTENANCE_TIMER_RANDOMIZED_DELAY_SEC}
EOF
)"
  balance_content="$(cat <<EOF
[Timer]
OnCalendar=
OnBootSec=30min
OnUnitActiveSec=${MAINTENANCE_BALANCE_INTERVAL}
AccuracySec=${MAINTENANCE_TIMER_ACCURACY_SEC}
Persistent=true
RandomizedDelaySec=${MAINTENANCE_TIMER_RANDOMIZED_DELAY_SEC}
EOF
)"
  run_cmd install -d -m 0755 "$BTRFS_SCRUB_DROPIN_DIR" "$BTRFS_BALANCE_DROPIN_DIR"
  write_root_file "$BTRFS_SCRUB_DROPIN_PATH" 0644 "$scrub_content"
  write_root_file "$BTRFS_BALANCE_DROPIN_PATH" 0644 "$balance_content"
}

render_all_configs() {
  run_cmd rm -f -- "$TIMESHIFT_WRAPPER_PATH" "$TIMESHIFT_LEGACY_LAUNCHER_PATH"
  render_timeshift_config
  render_timeshift_wrapper
  render_timeshift_desktop_override
  render_btrfsmaintenance_config
  render_grub_btrfs_config
  render_grub_btrfs_service
  render_btrfs_timer_overrides
}

refresh_grub_menu() {
  require_file "$GRUB_BTRFS_SCRIPT_PATH"
  run_cmd update-grub
  require_file "$GRUB_BTRFS_CFG_PATH"
  run_cmd "$GRUB_BTRFS_SCRIPT_PATH"
  run_cmd update-grub
  run_cmd grub-script-check "$GRUB_BTRFS_CFG_PATH"
}

enable_all_services() {
  capture_unit_states
  install_grub_btrfs_files
  run_cmd systemctl daemon-reload
  if command -v systemd-analyze >/dev/null 2>&1; then
    run_cmd systemd-analyze verify "$GRUB_BTRFS_SERVICE_PATH"
  fi
  run_cmd timeshift --check --scripted || true
  refresh_grub_menu
  run_cmd systemctl disable --now btrfsmaintenance-refresh.path >/dev/null 2>&1 || true
  run_cmd systemctl enable --now grub-btrfsd.service
  run_cmd systemctl enable --now btrfs-scrub.timer
  run_cmd systemctl enable --now btrfs-balance.timer
  run_cmd systemctl disable --now btrfs-defrag.timer >/dev/null 2>&1 || true
  run_cmd systemctl disable --now btrfs-trim.timer >/dev/null 2>&1 || true
  if [[ "${MAINTENANCE_ENABLE_FSTRIM}" == "yes" ]]; then
    run_cmd systemctl enable --now fstrim.timer
  fi
}

remove_maintenance_install() {
  run_cmd systemctl disable --now grub-btrfsd.service >/dev/null 2>&1 || true
  restore_unit_state "fstrim.timer" "STATE_FSTRIM_TIMER"
  restore_unit_state "btrfs-scrub.timer" "STATE_BTRFS_SCRUB_TIMER"
  restore_unit_state "btrfs-balance.timer" "STATE_BTRFS_BALANCE_TIMER"
  restore_unit_state "btrfs-defrag.timer" "STATE_BTRFS_DEFRAG_TIMER"
  restore_unit_state "btrfs-trim.timer" "STATE_BTRFS_TRIM_TIMER"
  restore_unit_state "btrfsmaintenance-refresh.path" "STATE_BTRFS_REFRESH_PATH"

  run_cmd rm -f -- "$GRUB_BTRFS_SCRIPT_PATH" "$GRUB_BTRFS_DAEMON_PATH" "$GRUB_BTRFS_SERVICE_PATH" "$GRUB_BTRFS_CONFIG_PATH" "$TIMESHIFT_CONFIG_PATH" "$TIMESHIFT_DESKTOP_OVERRIDE_PATH" "$TIMESHIFT_WRAPPER_PATH" "$TIMESHIFT_LEGACY_LAUNCHER_PATH" "$BTRFSMAINT_CONFIG_PATH"
  run_cmd rm -f -- "$BTRFS_SCRUB_DROPIN_PATH" "$BTRFS_BALANCE_DROPIN_PATH"
  run_cmd rmdir --ignore-fail-on-non-empty "$BTRFS_SCRUB_DROPIN_DIR" >/dev/null 2>&1 || true
  run_cmd rmdir --ignore-fail-on-non-empty "$BTRFS_BALANCE_DROPIN_DIR" >/dev/null 2>&1 || true
  run_cmd rmdir --ignore-fail-on-non-empty "$GRUB_BTRFS_CONFIG_DIR" >/dev/null 2>&1 || true
  run_cmd rmdir --ignore-fail-on-non-empty "$TIMESHIFT_CONFIG_DIR" >/dev/null 2>&1 || true
  run_cmd rm -rf -- "$GRUB_BTRFS_CLONE_DIR" "$MAINTENANCE_RUNTIME_ROOT"

  run_cmd systemctl daemon-reload
  run_cmd update-grub || true

  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none \
    apt remove "${apt_args[@]}" timeshift btrfsmaintenance || true
}
