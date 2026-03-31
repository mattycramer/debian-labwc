#!/usr/bin/env bash

readonly SYSTEMD_UNIT_DIR="/etc/systemd/system"
readonly SYSTEM_MOUNT_STATE_DIR="/var/lib/local-mounts"
readonly SYSTEM_MOUNT_STATE_FILE="$SYSTEM_MOUNT_STATE_DIR/managed-units.list"
readonly SYSTEM_AUTOMOUNT_IDLE_TIMEOUT="5min"

mount_config_has_entries() {
  awk '
    /^[[:space:]]*($|#)/ { next }
    { found = 1; exit 0 }
    END { exit(found ? 0 : 1) }
  ' "$MOUNTS_CONFIG_FILE"
}

validate_mount_source_token() {
  [[ "$1" =~ ^[A-Za-z0-9._:+-]+$ ]] || die "unsupported source token: $1"
}

validate_principal_token() {
  [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_.-]*[$]?$ ]] || die "unsupported principal token: $1"
}

resolve_principal_token() {
  local token="$1"
  local kind="$2"

  case "$token" in
    invoke)
      case "$kind" in
        user) printf '%s' "$SYSTEM_TARGET_USER" ;;
        group) printf '%s' "$SYSTEM_TARGET_GROUP" ;;
        *) die "unsupported principal kind: $kind" ;;
      esac
      ;;
    root)
      printf '%s' "root"
      ;;
    *)
      validate_principal_token "$token"
      printf '%s' "$token"
      ;;
  esac
}

resolve_mount_device_path() {
  local source="$1"
  local token

  case "$source" in
    LABEL=*)
      token="${source#LABEL=}"
      validate_mount_source_token "$token"
      printf '/dev/disk/by-label/%s' "$token"
      ;;
    UUID=*)
      token="${source#UUID=}"
      validate_mount_source_token "$token"
      printf '/dev/disk/by-uuid/%s' "$token"
      ;;
    PARTUUID=*)
      token="${source#PARTUUID=}"
      validate_mount_source_token "$token"
      printf '/dev/disk/by-partuuid/%s' "$token"
      ;;
    PARTLABEL=*)
      token="${source#PARTLABEL=}"
      validate_mount_source_token "$token"
      printf '/dev/disk/by-partlabel/%s' "$token"
      ;;
    /dev/*)
      printf '%s' "$source"
      ;;
    *)
      die "unsupported mount source: $source"
      ;;
  esac
}

validate_mount_timeout() {
  [[ "$1" =~ ^[0-9]+(ms|s|min|h)$ ]] || die "unsupported mount timeout: $1"
}

validate_automount_idle_timeout() {
  [[ -z "$1" || "$1" =~ ^([0-9]+(ms|s|min|h)|infinity)$ ]] || {
    die "unsupported automount idle timeout: $1"
  }
}

validate_permission_mode() {
  [[ "$1" =~ ^0?[0-7]{3,4}$ ]] || die "unsupported permission mode: $1"
}

validate_mount_option_list() {
  local mountpoint="$1"
  local fs_type="$2"
  local options="$3"
  local part

  [[ -n "$options" ]] || die "mount options are required for $mountpoint"
  IFS=',' read -r -a option_parts <<<"$options"
  for part in "${option_parts[@]}"; do
    [[ -n "$part" ]] || die "empty option component in mount options for $mountpoint"
    [[ "$part" != *[[:space:]]* ]] || die "mount option contains whitespace for $mountpoint: $part"
  done

  if [[ "$fs_type" == "btrfs" ]]; then
    [[ "$options" == *subvol=* || "$options" == *subvolid=* ]] || {
      die "btrfs mount $mountpoint must include subvol= or subvolid="
    }
  fi
}

validate_mount_entry() {
  local source="$1"
  local where="$2"
  local fs_type="$3"
  local options="$4"
  local timeout="$5"
  local owner_token="$6"
  local group_token="$7"
  local mode="$8"
  local automount_idle_timeout="${9:-}"

  [[ -n "$source" ]] || die "mount source is required"
  [[ "$where" == /* ]] || die "mount target must be absolute: $where"
  [[ "$where" != "/" ]] || die "refusing to manage / as a generated mount unit"
  [[ "$where" != *[[:space:]]* ]] || die "mount target cannot contain whitespace: $where"
  [[ -n "$fs_type" ]] || die "filesystem type is required for $where"
  [[ "$fs_type" != *[[:space:]]* ]] || die "filesystem type cannot contain whitespace: $fs_type"
  [[ "$timeout" != *[[:space:]]* ]] || die "mount timeout cannot contain whitespace: $timeout"

  resolve_mount_device_path "$source" >/dev/null
  validate_mount_option_list "$where" "$fs_type" "$options"
  validate_mount_timeout "$timeout"
  validate_automount_idle_timeout "$automount_idle_timeout"
  resolve_principal_token "$owner_token" user >/dev/null
  resolve_principal_token "$group_token" group >/dev/null
  validate_permission_mode "$mode"
}

mount_unit_name_from_target() {
  systemd-escape --path --suffix=mount "$1"
}

automount_unit_name_from_target() {
  systemd-escape --path --suffix=automount "$1"
}

device_unit_name_from_device_path() {
  systemd-escape --path --suffix=device "$1"
}

ownership_service_name_from_mount_unit() {
  local mount_unit="$1"
  printf '%s-ownership.service' "${mount_unit%.mount}"
}

activation_service_name_from_automount_unit() {
  local automount_unit="$1"
  printf '%s-activate.service' "${automount_unit%.automount}"
}

device_watch_path_name_from_automount_unit() {
  local automount_unit="$1"
  printf '%s-watch.path' "${automount_unit%.automount}"
}

current_mount_fstype() {
  findmnt -rn -T "$1" -o FSTYPE 2>/dev/null || true
}

current_mount_target() {
  findmnt -rn -T "$1" -o TARGET 2>/dev/null || true
}

mount_target_has_real_fs() {
  local mount_target
  local fs_type

  mount_target="$(current_mount_target "$1")"
  [[ "$mount_target" == "$1" ]] || return 1

  fs_type="$(current_mount_fstype "$1")"
  [[ -n "$fs_type" && "$fs_type" != "autofs" ]]
}

generate_mount_unit_file() {
  local source="$1"
  local where="$2"
  local fs_type="$3"
  local options="$4"
  local timeout="$5"
  local destination_path="$6"
  local device_path device_unit requires_path

  device_path="$(resolve_mount_device_path "$source")"
  device_unit="$(device_unit_name_from_device_path "$device_path")"
  requires_path="$(dirname -- "$where")"

  cat >"$destination_path" <<EOF
# Managed locally. Do not edit manually.
[Unit]
Description=Local mount for $where
Documentation=man:systemd.mount(5)
ConditionPathExists=$device_path
BindsTo=$device_unit
After=$device_unit
RequiresMountsFor=$requires_path

[Mount]
What=$device_path
Where=$where
Type=$fs_type
Options=$options
TimeoutSec=$timeout
EOF
}

generate_automount_unit_file() {
  local where="$1"
  local source="$2"
  local idle_timeout="${3:-}"
  local destination_path="$4"
  local device_path device_unit

  [[ -n "$idle_timeout" ]] || idle_timeout="$SYSTEM_AUTOMOUNT_IDLE_TIMEOUT"
  device_path="$(resolve_mount_device_path "$source")"
  device_unit="$(device_unit_name_from_device_path "$device_path")"

  cat >"$destination_path" <<EOF
# Managed locally. Do not edit manually.
[Unit]
Description=Local automount for $where
Documentation=man:systemd.automount(5)
ConditionPathExists=$device_path
BindsTo=$device_unit
After=$device_unit

[Automount]
Where=$where
DirectoryMode=0755
TimeoutIdleSec=$idle_timeout
EOF
}

generate_activation_service_file() {
  local where="$1"
  local source="$2"
  local automount_unit="$3"
  local destination_path="$4"
  local device_path device_unit

  device_path="$(resolve_mount_device_path "$source")"
  device_unit="$(device_unit_name_from_device_path "$device_path")"

  cat >"$destination_path" <<EOF
# Managed locally. Do not edit manually.
[Unit]
Description=Activate the automount for $where when the device is present
Documentation=man:systemd.path(5) man:systemd.service(5)
ConditionPathExists=$device_path
BindsTo=$device_unit
After=$device_unit

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl start $automount_unit
EOF
}

generate_device_watch_path_file() {
  local where="$1"
  local source="$2"
  local activation_service="$3"
  local destination_path="$4"
  local device_path

  device_path="$(resolve_mount_device_path "$source")"

  cat >"$destination_path" <<EOF
# Managed locally. Do not edit manually.
[Unit]
Description=Watch $device_path and activate the automount for $where
Documentation=man:systemd.path(5)

[Path]
PathExists=$device_path
Unit=$activation_service

[Install]
WantedBy=multi-user.target
EOF
}

generate_ownership_service_file() {
  local mount_unit="$1"
  local where="$2"
  local owner_token="$3"
  local group_token="$4"
  local mode="$5"
  local destination_path="$6"
  local owner_name group_name

  owner_name="$(resolve_principal_token "$owner_token" user)"
  group_name="$(resolve_principal_token "$group_token" group)"

  cat >"$destination_path" <<EOF
# Managed locally. Do not edit manually.
[Unit]
Description=Local ownership fixup for $where
Documentation=man:systemd.service(5)
Requires=$mount_unit
After=$mount_unit
ConditionPathIsMountPoint=$where

[Service]
Type=oneshot
EOF

  if [[ "$owner_name" != "root" ]]; then
    printf 'ExecStartPre=/usr/bin/getent passwd %s\n' "$owner_name" >>"$destination_path"
  fi
  if [[ "$group_name" != "root" ]]; then
    printf 'ExecStartPre=/usr/bin/getent group %s\n' "$group_name" >>"$destination_path"
  fi

  cat >>"$destination_path" <<EOF
ExecStart=/usr/bin/chown $owner_name:$group_name $where
ExecStart=/usr/bin/chmod ${mode#0} $where

[Install]
WantedBy=$mount_unit
EOF
}

build_mount_unit_candidates() {
  local destination_dir="$1"
  local manifest_path="$2"
  local line_no=0
  local source where fs_type options timeout owner_token group_token mode automount_idle_timeout extra
  local unit_name candidate_path automount_unit ownership_unit activation_service device_watch_path existing_target
  local idx
  local -a sources=()
  local -a targets=()
  local -a fs_types=()
  local -a options_list=()
  local -a timeouts=()
  local -a owner_tokens=()
  local -a group_tokens=()
  local -a modes=()
  local -a automount_idle_timeouts=()
  local -A seen_units=()
  local -A seen_targets=()

  : >"$manifest_path"
  while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    line_no=$((line_no + 1))
    raw_line="${raw_line%$'\r'}"

    [[ "$raw_line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$raw_line" =~ ^[[:space:]]*# ]] && continue

    IFS='|' read -r source where fs_type options timeout owner_token group_token mode automount_idle_timeout extra <<<"$raw_line"
    [[ -z "${extra:-}" ]] || die "invalid mount config line $line_no in $MOUNTS_CONFIG_FILE: expected 8 or 9 fields"

    validate_mount_entry "$source" "$where" "$fs_type" "$options" "$timeout" "$owner_token" "$group_token" "$mode" "$automount_idle_timeout"
    unit_name="$(mount_unit_name_from_target "$where")"

    for existing_target in "${targets[@]}"; do
      if [[ "$where" == "$existing_target/"* || "$existing_target" == "$where/"* ]]; then
        die "nested managed mount targets are not supported: $where conflicts with $existing_target"
      fi
    done

    [[ -z "${seen_units[$unit_name]:-}" ]] || die "duplicate mount unit target in $MOUNTS_CONFIG_FILE: $where"
    [[ -z "${seen_targets[$where]:-}" ]] || die "duplicate mount path in $MOUNTS_CONFIG_FILE: $where"
    seen_units["$unit_name"]=1
    seen_targets["$where"]=1

    sources+=("$source")
    targets+=("$where")
    fs_types+=("$fs_type")
    options_list+=("$options")
    timeouts+=("$timeout")
    owner_tokens+=("$owner_token")
    group_tokens+=("$group_token")
    modes+=("$mode")
    automount_idle_timeouts+=("$automount_idle_timeout")
  done <"$MOUNTS_CONFIG_FILE"

  mount_config_has_entries || die "no mount entries defined in $MOUNTS_CONFIG_FILE"

  for idx in "${!targets[@]}"; do
    source="${sources[$idx]}"
    where="${targets[$idx]}"
    fs_type="${fs_types[$idx]}"
    options="${options_list[$idx]}"
    timeout="${timeouts[$idx]}"
    owner_token="${owner_tokens[$idx]}"
    group_token="${group_tokens[$idx]}"
    mode="${modes[$idx]}"
    automount_idle_timeout="${automount_idle_timeouts[$idx]}"
    unit_name="$(mount_unit_name_from_target "$where")"

    candidate_path="$destination_dir/$unit_name"
    generate_mount_unit_file "$source" "$where" "$fs_type" "$options" "$timeout" "$candidate_path"
    printf '%s|static|\n' "$unit_name" >>"$manifest_path"

    automount_unit="$(automount_unit_name_from_target "$where")"
    [[ -z "${seen_units[$automount_unit]:-}" ]] || die "duplicate automount unit target in $MOUNTS_CONFIG_FILE: $where"
    seen_units["$automount_unit"]=1
    candidate_path="$destination_dir/$automount_unit"
    generate_automount_unit_file "$where" "$source" "$automount_idle_timeout" "$candidate_path"
    printf '%s|static|\n' "$automount_unit" >>"$manifest_path"

    activation_service="$(activation_service_name_from_automount_unit "$automount_unit")"
    [[ -z "${seen_units[$activation_service]:-}" ]] || die "duplicate activation service target in $MOUNTS_CONFIG_FILE: $where"
    seen_units["$activation_service"]=1
    candidate_path="$destination_dir/$activation_service"
    generate_activation_service_file "$where" "$source" "$automount_unit" "$candidate_path"
    printf '%s|static|\n' "$activation_service" >>"$manifest_path"

    device_watch_path="$(device_watch_path_name_from_automount_unit "$automount_unit")"
    [[ -z "${seen_units[$device_watch_path]:-}" ]] || die "duplicate device-watch path target in $MOUNTS_CONFIG_FILE: $where"
    seen_units["$device_watch_path"]=1
    candidate_path="$destination_dir/$device_watch_path"
    generate_device_watch_path_file "$where" "$source" "$activation_service" "$candidate_path"
    printf '%s|path|%s\n' "$device_watch_path" "$activation_service" >>"$manifest_path"

    ownership_unit="$(ownership_service_name_from_mount_unit "$unit_name")"
    [[ -z "${seen_units[$ownership_unit]:-}" ]] || die "duplicate ownership service target in $MOUNTS_CONFIG_FILE: $where"
    seen_units["$ownership_unit"]=1
    candidate_path="$destination_dir/$ownership_unit"
    generate_ownership_service_file "$unit_name" "$where" "$owner_token" "$group_token" "$mode" "$candidate_path"
    printf '%s|ownership|%s\n' "$ownership_unit" "$unit_name" >>"$manifest_path"
  done
}

list_mount_targets() {
  awk -F'|' '
    /^[[:space:]]*($|#)/ { next }
    NF >= 2 { print $2 }
  ' "$MOUNTS_CONFIG_FILE"
}

read_mount_policies() {
  awk -F'|' '
    /^[[:space:]]*($|#)/ { next }
    NF >= 8 { print $2 "|" $6 "|" $7 "|" $8 }
  ' "$MOUNTS_CONFIG_FILE"
}

ensure_mount_target_directories() {
  local mountpoint

  while IFS= read -r mountpoint; do
    [[ -n "$mountpoint" ]] || continue
    run_cmd install -d -m 0755 -o root -g root "$mountpoint"
    run_cmd chown root:root "$mountpoint"
    run_cmd chmod 0755 "$mountpoint"
  done < <(list_mount_targets)
}

read_managed_mount_manifest() {
  [[ -f "$SYSTEM_MOUNT_STATE_FILE" ]] || return 0
  awk '
    /^[[:space:]]*($|#)/ { next }
    { print }
  ' "$SYSTEM_MOUNT_STATE_FILE"
}

validate_mount_unit_candidates() {
  local candidate_dir="$1"
  local -a candidate_units=()

  mapfile -t candidate_units < <(find "$candidate_dir" -maxdepth 1 -type f \( -name '*.mount' -o -name '*.automount' -o -name '*.service' -o -name '*.path' \) | sort)
  ((${#candidate_units[@]} > 0)) || die "no mount unit candidates were generated"
  run_cmd systemd-analyze verify "${candidate_units[@]}"
}

install_mount_state_manifest() {
  local source_path="$1"

  run_cmd install -d -m 0755 -o root -g root "$SYSTEM_MOUNT_STATE_DIR"
  run_cmd install -m 0644 -o root -g root "$source_path" "$SYSTEM_MOUNT_STATE_FILE"
}

apply_managed_mount_units() {
  local candidate_dir manifest_path
  local unit_name state hook source_path destination_path
  local -A desired_units=()

  ensure_mount_target_directories
  candidate_dir="$(mktemp -d)"
  manifest_path="$(mktemp)"
  build_mount_unit_candidates "$candidate_dir" "$manifest_path"
  validate_mount_unit_candidates "$candidate_dir"

  while IFS='|' read -r unit_name state hook; do
    [[ -n "$unit_name" ]] || continue
    desired_units["$unit_name"]=1
  done <"$manifest_path"

  while IFS='|' read -r unit_name state hook; do
    [[ -n "$unit_name" ]] || continue
    [[ -n "${desired_units[$unit_name]:-}" ]] && continue
    run_cmd systemctl stop "$unit_name" >/dev/null 2>&1 || true
    if [[ "$state" == "path" || "$state" == "ownership" ]]; then
      run_cmd systemctl disable "$unit_name" >/dev/null 2>&1 || true
    fi
    run_cmd rm -f -- "$SYSTEMD_UNIT_DIR/$unit_name"
  done < <(read_managed_mount_manifest)

  while IFS='|' read -r unit_name state hook; do
    [[ -n "$unit_name" ]] || continue
    source_path="$candidate_dir/$unit_name"
    destination_path="$SYSTEMD_UNIT_DIR/$unit_name"
    if [[ -f "$destination_path" ]] && cmp -s "$source_path" "$destination_path"; then
      continue
    fi
    run_cmd install -m 0644 -o root -g root "$source_path" "$destination_path"
  done <"$manifest_path"

  install_mount_state_manifest "$manifest_path"
  run_cmd systemctl daemon-reload

  while IFS='|' read -r unit_name state hook; do
    [[ -n "$unit_name" ]] || continue
    case "$state" in
      path)
        run_cmd systemctl enable "$unit_name" >/dev/null
        run_cmd systemctl start "$unit_name"
        if [[ -n "$hook" ]]; then
          # Avoid blocking the installer when the backing device is absent.
          run_cmd systemctl start --no-block "$hook" >/dev/null 2>&1 || true
        fi
        ;;
      ownership)
        run_cmd systemctl enable "$unit_name" >/dev/null
        ;;
      static)
        ;;
      *)
        die "unsupported managed unit state: $state"
        ;;
    esac
  done <"$manifest_path"

  while IFS='|' read -r unit_name state hook; do
    [[ "$state" == "ownership" ]] || continue
    if run_cmd systemctl is-active "$hook" >/dev/null 2>&1; then
      run_cmd systemctl start "$unit_name"
    fi
  done <"$manifest_path"

  rm -rf -- "$candidate_dir"
  rm -f -- "$manifest_path"
  log_info "updated generated systemd mount units"
}

remove_managed_mount_units() {
  local removed=0
  local unit_name state hook

  while IFS='|' read -r unit_name state hook; do
    [[ -n "$unit_name" ]] || continue
    run_cmd systemctl stop "$unit_name" >/dev/null 2>&1 || true
    if [[ "$state" == "path" || "$state" == "ownership" ]]; then
      run_cmd systemctl disable "$unit_name" >/dev/null 2>&1 || true
    fi
    run_cmd rm -f -- "$SYSTEMD_UNIT_DIR/$unit_name"
    removed=1
  done < <(read_managed_mount_manifest)

  run_cmd rm -f -- "$SYSTEM_MOUNT_STATE_FILE"
  if [[ -d "$SYSTEM_MOUNT_STATE_DIR" ]] && [[ -z "$(find "$SYSTEM_MOUNT_STATE_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    run_cmd rmdir -- "$SYSTEM_MOUNT_STATE_DIR"
  fi

  if [[ "$removed" -eq 1 ]]; then
    run_cmd systemctl daemon-reload
    log_info "removed generated systemd mount units"
  else
    log_info "no generated systemd mount units present"
  fi
}

verify_managed_mount_units() {
  local candidate_dir manifest_path
  local unit_name state hook installed_path candidate_path

  candidate_dir="$(mktemp -d)"
  manifest_path="$(mktemp)"
  build_mount_unit_candidates "$candidate_dir" "$manifest_path"
  validate_mount_unit_candidates "$candidate_dir"
  require_file "$SYSTEM_MOUNT_STATE_FILE"
  cmp -s "$manifest_path" "$SYSTEM_MOUNT_STATE_FILE" || die "$SYSTEM_MOUNT_STATE_FILE does not match the generated mount-unit manifest"

  while IFS='|' read -r unit_name state hook; do
    [[ -n "$unit_name" ]] || continue
    installed_path="$SYSTEMD_UNIT_DIR/$unit_name"
    candidate_path="$candidate_dir/$unit_name"
    require_file "$installed_path"
    cmp -s "$candidate_path" "$installed_path" || die "$installed_path does not match the generated mount-unit state"
    case "$state" in
      path)
        run_cmd systemctl is-enabled "$unit_name" >/dev/null
        run_cmd systemctl is-active "$unit_name" >/dev/null
        ;;
      ownership)
        run_cmd systemctl is-enabled "$unit_name" >/dev/null
        ;;
      static)
        ;;
      *)
        die "unsupported managed unit state: $state"
        ;;
    esac
  done <"$manifest_path"

  rm -rf -- "$candidate_dir"
  rm -f -- "$manifest_path"
}

validate_managed_mount_units() {
  local candidate_dir manifest_path

  candidate_dir="$(mktemp -d)"
  manifest_path="$(mktemp)"
  build_mount_unit_candidates "$candidate_dir" "$manifest_path"
  validate_mount_unit_candidates "$candidate_dir"
  rm -rf -- "$candidate_dir"
  rm -f -- "$manifest_path"
}
