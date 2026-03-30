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
}

mount_unit_name_from_target() {
  systemd-escape --path --suffix=mount "$1"
}

automount_unit_name_from_target() {
  systemd-escape --path --suffix=automount "$1"
}

generate_mount_unit_file() {
  local source="$1"
  local where="$2"
  local fs_type="$3"
  local options="$4"
  local timeout="$5"
  local parent_mount_unit="$6"
  local destination_path="$7"
  local device_path requires_path

  device_path="$(resolve_mount_device_path "$source")"
  requires_path="$(dirname -- "$where")"

  cat >"$destination_path" <<EOF
# Managed locally. Do not edit manually.
[Unit]
Description=Local mount for $where
Documentation=man:systemd.mount(5)
ConditionPathExists=$device_path
RequiresMountsFor=$requires_path

[Mount]
What=$device_path
Where=$where
Type=$fs_type
Options=$options
TimeoutSec=$timeout
EOF

  if [[ -n "$parent_mount_unit" ]]; then
    cat >>"$destination_path" <<EOF

[Install]
WantedBy=$parent_mount_unit
EOF
  fi
}

generate_automount_unit_file() {
  local where="$1"
  local destination_path="$2"

  cat >"$destination_path" <<EOF
# Managed locally. Do not edit manually.
[Unit]
Description=Local automount for $where
Documentation=man:systemd.automount(5)

[Automount]
Where=$where
DirectoryMode=0755
TimeoutIdleSec=$SYSTEM_AUTOMOUNT_IDLE_TIMEOUT

[Install]
WantedBy=local-fs.target
EOF
}

build_mount_unit_candidates() {
  local destination_dir="$1"
  local manifest_path="$2"
  local line_no=0
  local source where fs_type options timeout extra
  local unit_name parent_path parent_unit candidate_path automount_unit
  local parent_dir idx
  local -a sources=()
  local -a targets=()
  local -a fs_types=()
  local -a options_list=()
  local -a timeouts=()
  local -A seen_units=()
  local -A seen_targets=()
  local -A target_exists=()
  local -A mount_unit_by_target=()

  : >"$manifest_path"
  while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    line_no=$((line_no + 1))
    raw_line="${raw_line%$'\r'}"

    [[ "$raw_line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$raw_line" =~ ^[[:space:]]*# ]] && continue

    IFS='|' read -r source where fs_type options timeout extra <<<"$raw_line"
    [[ -z "${extra:-}" ]] || die "invalid mount config line $line_no in $MOUNTS_CONFIG_FILE: expected 5 fields"

    validate_mount_entry "$source" "$where" "$fs_type" "$options" "$timeout"
    unit_name="$(mount_unit_name_from_target "$where")"

    [[ -z "${seen_units[$unit_name]:-}" ]] || die "duplicate mount unit target in $MOUNTS_CONFIG_FILE: $where"
    [[ -z "${seen_targets[$where]:-}" ]] || die "duplicate mount path in $MOUNTS_CONFIG_FILE: $where"
    seen_units["$unit_name"]=1
    seen_targets["$where"]=1
    target_exists["$where"]=1
    mount_unit_by_target["$where"]="$unit_name"

    sources+=("$source")
    targets+=("$where")
    fs_types+=("$fs_type")
    options_list+=("$options")
    timeouts+=("$timeout")
  done <"$MOUNTS_CONFIG_FILE"

  mount_config_has_entries || die "no mount entries defined in $MOUNTS_CONFIG_FILE"

  for idx in "${!targets[@]}"; do
    source="${sources[$idx]}"
    where="${targets[$idx]}"
    fs_type="${fs_types[$idx]}"
    options="${options_list[$idx]}"
    timeout="${timeouts[$idx]}"
    unit_name="${mount_unit_by_target[$where]}"

    parent_path=""
    parent_dir="$(dirname -- "$where")"
    while [[ "$parent_dir" != "/" && "$parent_dir" != "." ]]; do
      if [[ -n "${target_exists[$parent_dir]:-}" ]]; then
        parent_path="$parent_dir"
        break
      fi
      parent_dir="$(dirname -- "$parent_dir")"
    done

    parent_unit=""
    if [[ -n "$parent_path" ]]; then
      parent_unit="${mount_unit_by_target[$parent_path]}"
      candidate_path="$destination_dir/$unit_name"
      generate_mount_unit_file "$source" "$where" "$fs_type" "$options" "$timeout" "$parent_unit" "$candidate_path"
      printf '%s|enabled\n' "$unit_name" >>"$manifest_path"
      continue
    fi

    candidate_path="$destination_dir/$unit_name"
    generate_mount_unit_file "$source" "$where" "$fs_type" "$options" "$timeout" "" "$candidate_path"
    printf '%s|static\n' "$unit_name" >>"$manifest_path"

    automount_unit="$(automount_unit_name_from_target "$where")"
    [[ -z "${seen_units[$automount_unit]:-}" ]] || die "duplicate automount unit target in $MOUNTS_CONFIG_FILE: $where"
    seen_units["$automount_unit"]=1
    candidate_path="$destination_dir/$automount_unit"
    generate_automount_unit_file "$where" "$candidate_path"
    printf '%s|automount\n' "$automount_unit" >>"$manifest_path"
  done
}

list_mount_targets() {
  awk -F'|' '
    /^[[:space:]]*($|#)/ { next }
    NF >= 2 { print $2 }
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
  mapfile -t candidate_units < <(find "$candidate_dir" -maxdepth 1 -type f \( -name '*.mount' -o -name '*.automount' \) | sort)
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
  local unit_name state source_path destination_path
  local -A desired_units=()

  ensure_mount_target_directories
  candidate_dir="$(mktemp -d)"
  manifest_path="$(mktemp)"
  build_mount_unit_candidates "$candidate_dir" "$manifest_path"
  validate_mount_unit_candidates "$candidate_dir"

  while IFS='|' read -r unit_name state; do
    [[ -n "$unit_name" ]] || continue
    desired_units["$unit_name"]=1
  done <"$manifest_path"

  while IFS='|' read -r unit_name state; do
    [[ -n "$unit_name" ]] || continue
    [[ -n "${desired_units[$unit_name]:-}" ]] && continue
    run_cmd systemctl stop "$unit_name" >/dev/null 2>&1 || true
    run_cmd systemctl disable "$unit_name" >/dev/null 2>&1 || true
    run_cmd rm -f -- "$SYSTEMD_UNIT_DIR/$unit_name"
  done < <(read_managed_mount_manifest)

  while IFS='|' read -r unit_name state; do
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

  while IFS='|' read -r unit_name state; do
    [[ -n "$unit_name" ]] || continue
    case "$state" in
      automount)
        run_cmd systemctl enable "$unit_name" >/dev/null
        run_cmd systemctl start "$unit_name"
        ;;
      enabled)
        run_cmd systemctl enable "$unit_name" >/dev/null
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
  log_info "updated generated systemd mount units"
}

remove_managed_mount_units() {
  local removed=0
  local unit_name state

  while IFS='|' read -r unit_name state; do
    [[ -n "$unit_name" ]] || continue
    run_cmd systemctl stop "$unit_name" >/dev/null 2>&1 || true
    run_cmd systemctl disable "$unit_name" >/dev/null 2>&1 || true
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
  local unit_name state installed_path candidate_path

  candidate_dir="$(mktemp -d)"
  manifest_path="$(mktemp)"
  build_mount_unit_candidates "$candidate_dir" "$manifest_path"
  validate_mount_unit_candidates "$candidate_dir"
  require_file "$SYSTEM_MOUNT_STATE_FILE"
  cmp -s "$manifest_path" "$SYSTEM_MOUNT_STATE_FILE" || die "$SYSTEM_MOUNT_STATE_FILE does not match the generated mount-unit manifest"

  while IFS='|' read -r unit_name state; do
    [[ -n "$unit_name" ]] || continue
    installed_path="$SYSTEMD_UNIT_DIR/$unit_name"
    candidate_path="$candidate_dir/$unit_name"
    require_file "$installed_path"
    cmp -s "$candidate_path" "$installed_path" || die "$installed_path does not match the generated mount-unit state"
    case "$state" in
      automount)
        run_cmd systemctl is-enabled "$unit_name" >/dev/null
        run_cmd systemctl is-active "$unit_name" >/dev/null
        ;;
      enabled)
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
