#!/usr/bin/env bash

readonly SYSTEM_HOME_MODE="0750"
readonly SYSTEM_DATA_PATH_SPECS=(
  "/data|root|root|0755"
  "/data/backup|invoke|invoke|0700"
  "/data/cfg|invoke|invoke|0700"
  "/data/cicd|root|root|0755"
  "/data/codex|invoke|invoke|0750"
  "/data/mnt|root|root|0755"
  "/data/services|invoke|invoke|0700"
  "/data/testing|invoke|invoke|0700"
  "/data/usr|root|root|0755"
  "/data/vault|root|root|0755"
  "/data/workspace|invoke|invoke|0750"
)

readonly SYSTEM_HOME_DIR_SPECS=(
  ".config|0750|tree"
  ".local|0750|tree"
  ".local/bin|0750|dir"
  ".local/share|0750|tree"
  ".local/share/keyrings|0700|tree"
  ".local/state|0700|tree"
  ".cache|0700|tree"
  ".ssh|0700|tree"
  ".gnupg|0700|tree"
  "Desktop|0750|dir"
  "Downloads|0750|dir"
  "Templates|0750|dir"
  "Public|0750|dir"
  "Documents|0750|dir"
  "Music|0750|dir"
  "Pictures|0750|dir"
  "Videos|0750|dir"
)

resolve_path_principal() {
  local token="$1"

  case "$token" in
    invoke) printf '%s' "$SYSTEM_TARGET_USER" ;;
    root) printf '%s' "root" ;;
    *) die "unsupported path principal token: $token" ;;
  esac
}

ensure_directory_state() {
  local path="$1"
  local owner="$2"
  local group="$3"
  local mode="$4"

  run_cmd install -d -m "$mode" -o "$owner" -g "$group" "$path"
  run_cmd chown "$owner:$group" "$path"
  run_cmd chmod "$mode" "$path"
}

repair_tree_ownership() {
  local path="$1"

  [[ -e "$path" ]] || return 0
  run_cmd find -P "$path" -exec chown -h "$SYSTEM_TARGET_USER:$SYSTEM_TARGET_GROUP" {} +
}

apply_system_path_permissions() {
  local spec path owner_token group_token mode owner group

  for spec in "${SYSTEM_DATA_PATH_SPECS[@]}"; do
    IFS='|' read -r path owner_token group_token mode <<<"$spec"
    owner="$(resolve_path_principal "$owner_token")"
    group="$(resolve_path_principal "$group_token")"
    ensure_directory_state "$path" "$owner" "$group" "$mode"
  done
}

apply_home_permissions() {
  local spec relative_path mode scope path

  ensure_directory_state "$SYSTEM_TARGET_HOME" "$SYSTEM_TARGET_USER" "$SYSTEM_TARGET_GROUP" "$SYSTEM_HOME_MODE"

  for spec in "${SYSTEM_HOME_DIR_SPECS[@]}"; do
    IFS='|' read -r relative_path mode scope <<<"$spec"
    path="$SYSTEM_TARGET_HOME/$relative_path"
    ensure_directory_state "$path" "$SYSTEM_TARGET_USER" "$SYSTEM_TARGET_GROUP" "$mode"
    if [[ "$scope" == "tree" ]]; then
      repair_tree_ownership "$path"
    fi
  done
}
