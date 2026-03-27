#!/usr/bin/env bash

package_is_installed() {
  dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null | grep -F "install ok installed" >/dev/null
}

verify_packages() {
  local pkg
  for pkg in timeshift btrfsmaintenance btrfs-progs inotify-tools grub-common grub2-common; do
    package_is_installed "$pkg" || die "package '$pkg' is not installed"
  done
}

verify_paths() {
  require_file "$TIMESHIFT_CONFIG_PATH"
  require_file "$GRUB_BTRFS_CONFIG_PATH"
  require_file "$GRUB_BTRFS_SCRIPT_PATH"
  require_file "$GRUB_BTRFS_DAEMON_PATH"
  require_file "$GRUB_BTRFS_SERVICE_PATH"
  require_file "$GRUB_BTRFS_CFG_PATH"
  require_file "$GRUB_CFG_PATH"
  require_file "$GRUB_CUSTOM_CFG_PATH"
  require_file "$BTRFSMAINT_CONFIG_PATH"
  require_file "$BTRFS_SCRUB_DROPIN_PATH"
  require_file "$BTRFS_BALANCE_DROPIN_PATH"
  require_file "$GRUB_BTRFS_COMMIT_FILE"
}

verify_detection() {
  [[ "$MAINTENANCE_BTRFS_PARTITION_COUNT" =~ ^[1-9][0-9]*$ ]] || die "expected one or more Btrfs partitions, found '${MAINTENANCE_BTRFS_PARTITION_COUNT}'"
  [[ "$MAINTENANCE_BTRFS_DEVICE_COUNT" =~ ^[1-9][0-9]*$ ]] || die "expected one or more mounted Btrfs block devices, found '${MAINTENANCE_BTRFS_DEVICE_COUNT}'"
  [[ -n "$MAINTENANCE_ROOT_BTRFS_SOURCE" ]] || die "missing detected root Btrfs source"
  [[ -n "$MAINTENANCE_ROOT_BTRFS_UUID" ]] || die "missing detected root Btrfs UUID"
  [[ -n "$MAINTENANCE_ROOT_BTRFS_KERNEL_FLAGS" ]] || die "missing derived root Btrfs kernel flags"
  printf '%s\n' "$MAINTENANCE_BTRFS_PARTITION_LIST" | grep -F "$MAINTENANCE_ROOT_BTRFS_SOURCE" >/dev/null || die "root Btrfs source is not in the detected partition list"
  [[ -z "$MAINTENANCE_UNMOUNTED_BTRFS_PARTITION_LIST" ]] || die "unmounted Btrfs partitions are present and would be skipped by maintenance: ${MAINTENANCE_UNMOUNTED_BTRFS_PARTITION_LIST}"
}

verify_timeshift_config() {
  grep -F "\"backup_device_uuid\" : \"${MAINTENANCE_ROOT_BTRFS_UUID}\"" "$TIMESHIFT_CONFIG_PATH" >/dev/null || die "Timeshift config missing root Btrfs snapshot device UUID"
  grep -F '"btrfs_mode" : "true"' "$TIMESHIFT_CONFIG_PATH" >/dev/null || die "Timeshift config is not pinned to Btrfs mode"
  grep -F "\"schedule_weekly\" : \"${TIMESHIFT_SCHEDULE_WEEKLY}\"" "$TIMESHIFT_CONFIG_PATH" >/dev/null || die "Timeshift config missing weekly schedule setting"
}

verify_grub_btrfs_config() {
  local snapshot_kernel_parameters
  snapshot_kernel_parameters="$(grub_btrfs_snapshot_kernel_parameters)"
  grep -F 'GRUB_BTRFS_GRUB_DIRNAME="/boot/grub"' "$GRUB_BTRFS_CONFIG_PATH" >/dev/null || die "grub-btrfs config missing Debian grub dir"
  grep -F "GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS=\"${snapshot_kernel_parameters}\"" "$GRUB_BTRFS_CONFIG_PATH" >/dev/null || die "grub-btrfs config missing preseed-aligned snapshot kernel parameters"
  grep -F "$GRUB_BTRFS_REPO_REF" "$GRUB_BTRFS_COMMIT_FILE" >/dev/null || die "grub-btrfs commit marker is wrong"
  grep -F 'ExecStart=/usr/local/bin/grub-btrfsd --syslog --timeshift-auto' "$GRUB_BTRFS_SERVICE_PATH" >/dev/null || die "grub-btrfsd service missing timeshift-auto mode"
  grep -F 'grub-btrfs.cfg' "$GRUB_CFG_PATH" >/dev/null || die "grub.cfg does not source grub-btrfs.cfg"
  grep -F 'custom.cfg' "$GRUB_CFG_PATH" >/dev/null || die "grub.cfg no longer sources custom.cfg"
  [[ -x /etc/grub.d/41_custom ]] || die "stock /etc/grub.d/41_custom is missing or not executable"
}

verify_btrfsmaintenance_config() {
  grep -F 'BTRFS_SCRUB_MOUNTPOINTS="auto"' "$BTRFSMAINT_CONFIG_PATH" >/dev/null || die "btrfsmaintenance scrub is not configured for all mounted Btrfs devices"
  grep -F 'BTRFS_BALANCE_MOUNTPOINTS="auto"' "$BTRFSMAINT_CONFIG_PATH" >/dev/null || die "btrfsmaintenance balance is not configured for all mounted Btrfs devices"
  grep -F 'BTRFS_DEFRAG_PERIOD="none"' "$BTRFSMAINT_CONFIG_PATH" >/dev/null || die "btrfsmaintenance defrag is not disabled"
  grep -F 'BTRFS_TRIM_PERIOD="none"' "$BTRFSMAINT_CONFIG_PATH" >/dev/null || die "btrfsmaintenance trim is not disabled in favor of fstrim.timer"
  grep -F "OnUnitActiveSec=${MAINTENANCE_SCRUB_INTERVAL}" "$BTRFS_SCRUB_DROPIN_PATH" >/dev/null || die "scrub timer override is not set to the requested interval"
  grep -F "OnUnitActiveSec=${MAINTENANCE_BALANCE_INTERVAL}" "$BTRFS_BALANCE_DROPIN_PATH" >/dev/null || die "balance timer override is not set to the requested interval"
}

verify_services_enabled() {
  systemctl is-enabled grub-btrfsd.service >/dev/null 2>&1 || die "grub-btrfsd.service is not enabled"
  systemctl is-enabled btrfs-scrub.timer >/dev/null 2>&1 || die "btrfs-scrub.timer is not enabled"
  systemctl is-enabled btrfs-balance.timer >/dev/null 2>&1 || die "btrfs-balance.timer is not enabled"
  systemctl is-enabled fstrim.timer >/dev/null 2>&1 || die "fstrim.timer is not enabled"
  ! systemctl is-enabled btrfs-defrag.timer >/dev/null 2>&1 || die "btrfs-defrag.timer should be disabled"
  ! systemctl is-enabled btrfs-trim.timer >/dev/null 2>&1 || die "btrfs-trim.timer should be disabled"
  find /etc/cron.d /etc/cron.hourly -maxdepth 1 -type f -name "$TIMESHIFT_HOURLY_CRON_NAME" 2>/dev/null | grep -q . || die "Timeshift did not export its hourly scheduler hook"
}

verify_install() {
  verify_packages
  verify_paths
  verify_detection
  verify_timeshift_config
  verify_grub_btrfs_config
  verify_btrfsmaintenance_config
  verify_services_enabled
  log_info "verification completed"
}
