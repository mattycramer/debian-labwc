#!/usr/bin/env bash

path_state() {
  stat -c '%U:%G:%a' "$1"
}

assert_directory_state() {
  local path="$1"
  local owner="$2"
  local group="$3"
  local mode="$4"
  local expected actual

  require_dir "$path"
  expected="${owner}:${group}:${mode#0}"
  actual="$(path_state "$path")"
  [[ "$actual" == "$expected" ]] || die "unexpected directory state for $path: expected $expected, found $actual"
}

assert_tree_has_no_root_owned_entries() {
  local path="$1"
  local first_match

  [[ -e "$path" ]] || return 0
  first_match="$(find -P "$path" -xdev \( -user root -o -group root \) -print -quit)"
  [[ -z "$first_match" ]] || die "root-owned content remains under $path: $first_match"
}

verify_path_is_nested_under_any() {
  local path="$1"
  local root
  shift || true

  for root in "$@"; do
    [[ "$path" == "$root" || "$path" == "$root/"* ]] && return 0
  done
  return 1
}

verify_system_path_permissions() {
  local spec path owner_token group_token mode owner group

  for spec in "${SYSTEM_DATA_PATH_SPECS[@]}"; do
    IFS='|' read -r path owner_token group_token mode <<<"$spec"
    owner="$(resolve_path_principal "$owner_token")"
    group="$(resolve_path_principal "$group_token")"
    assert_directory_state "$path" "$owner" "$group" "$mode"
  done
}

verify_home_permissions() {
  local spec relative_path mode scope path
  local -a verified_tree_roots=()

  assert_directory_state "$SYSTEM_TARGET_HOME" "$SYSTEM_TARGET_USER" "$SYSTEM_TARGET_GROUP" "$SYSTEM_HOME_MODE"

  for spec in "${SYSTEM_HOME_DIR_SPECS[@]}"; do
    IFS='|' read -r relative_path mode scope <<<"$spec"
    path="$SYSTEM_TARGET_HOME/$relative_path"
    assert_directory_state "$path" "$SYSTEM_TARGET_USER" "$SYSTEM_TARGET_GROUP" "$mode"
    if [[ "$scope" == "tree" ]]; then
      if verify_path_is_nested_under_any "$path" "${verified_tree_roots[@]}"; then
        continue
      fi
      assert_tree_has_no_root_owned_entries "$path"
      verified_tree_roots+=("$path")
    fi
  done
}

verify_mount_targets() {
  local mountpoint owner_token group_token mode owner group expected actual

  while IFS='|' read -r mountpoint owner_token group_token mode; do
    [[ -n "$mountpoint" ]] || continue
    require_dir "$mountpoint"
    if mount_target_has_real_fs "$mountpoint"; then
      owner="$(resolve_principal_token "$owner_token" user)"
      group="$(resolve_principal_token "$group_token" group)"
      expected="${owner}:${group}:${mode#0}"
      actual="$(path_state "$mountpoint")"
      [[ "$actual" == "$expected" ]] || die "unexpected mounted directory state for $mountpoint: expected $expected, found $actual"
    fi
  done < <(read_mount_policies)
}

verify_install() {
  verify_managed_sid_repository
  verify_managed_mount_units
  verify_managed_secure_boot
  verify_managed_sudoers
  verify_system_account_policies
  verify_mount_targets
  verify_system_path_permissions
  verify_home_permissions
  log_info "verification completed"
}
