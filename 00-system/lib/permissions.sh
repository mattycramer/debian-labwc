#!/usr/bin/env bash

readonly SYSTEM_HOME_MODE="0750"
readonly SYSTEM_DATA_PATH_SPECS=(
  "/data|root|root|0755"
  "/data/backup|invoke|invoke|0700"
  "/data/cfg|invoke|invoke|0700"
  "/data/cicd|root|root|0755"
  "/data/codex|invoke|invoke|0750"
  "/data/mnt|root|root|0755"
  "/data/mnt/g-drive|root|root|0755"
  "/data/services|invoke|invoke|0700"
  "/data/testing|invoke|invoke|0700"
  "/data/usr|root|root|0755"
  "/data/vault|root|root|0755"
  "/data/workspace|invoke|invoke|0750"
)

readonly SYSTEM_POOL_PATH_SPECS=(
  "/pool|root|root|0755|dir|no"
  "/pool/builds|invoke|invoke|0750|tree|yes"
  "/pool/builds/labwc|invoke|invoke|0750|tree|yes"
  "/pool/builds/rust|invoke|invoke|0750|tree|yes"
  "/pool/builds/rust/rustup|invoke|invoke|0700|tree|yes"
  "/pool/builds/rust/cargo|invoke|invoke|0700|tree|yes"
  "/pool/builds/rust/target|invoke|invoke|0700|tree|yes"
  "/pool/builds/go|invoke|invoke|0750|tree|yes"
  "/pool/builds/go/bin|invoke|invoke|0750|dir|yes"
  "/pool/builds/python|invoke|invoke|0750|tree|yes"
  "/pool/builds/python/pipx|invoke|invoke|0700|tree|yes"
  "/pool/builds/python/virtualenvs|invoke|invoke|0700|tree|yes"
  "/pool/builds/python/poetry-virtualenvs|invoke|invoke|0700|tree|yes"
  "/pool/builds/pypoetry|invoke|invoke|0750|tree|yes"
  "/pool/builds/pypoetry/data|invoke|invoke|0700|tree|yes"
  "/pool/builds/pypoetry/python|invoke|invoke|0700|tree|yes"
  "/pool/builds/node_modules|invoke|invoke|0750|tree|yes"
  "/pool/builds/node_modules/npm|invoke|invoke|0700|tree|yes"
  "/pool/builds/node_modules/pnpm|invoke|invoke|0750|tree|yes"
  "/pool/builds/node_modules/pnpm/global|invoke|invoke|0700|tree|yes"
  "/pool/builds/node_modules/pnpm/bin|invoke|invoke|0750|dir|yes"
  "/pool/builds/node_modules/yarn|invoke|invoke|0750|tree|yes"
  "/pool/builds/node_modules/yarn/global|invoke|invoke|0700|tree|yes"
  "/pool/builds/maven|invoke|invoke|0700|tree|yes"
  "/pool/builds/uv|invoke|invoke|0750|tree|yes"
  "/pool/builds/uv/tools|invoke|invoke|0700|tree|yes"
  "/pool/builds/uv/bin|invoke|invoke|0750|dir|yes"
  "/pool/builds/uv/python|invoke|invoke|0700|tree|yes"
  "/pool/builds/dotnet|invoke|invoke|0750|tree|yes"
  "/pool/builds/dotnet/cli|invoke|invoke|0700|tree|yes"
  "/pool/builds/ruby|invoke|invoke|0750|tree|yes"
  "/pool/builds/ruby/gems|invoke|invoke|0700|tree|yes"
  "/pool/builds/bundle|invoke|invoke|0750|tree|yes"
  "/pool/builds/bundle/home|invoke|invoke|0700|tree|yes"
  "/pool/builds/bundle/plugins|invoke|invoke|0700|tree|yes"
  "/pool/builds/composer|invoke|invoke|0700|tree|yes"
  "/pool/builds/sbt|invoke|invoke|0700|tree|yes"
  "/pool/cache|invoke|invoke|0750|tree|yes"
  "/pool/cache/go|invoke|invoke|0700|tree|yes"
  "/pool/cache/go/build|invoke|invoke|0700|tree|yes"
  "/pool/cache/go/mod|invoke|invoke|0700|tree|yes"
  "/pool/cache/pip|invoke|invoke|0700|tree|yes"
  "/pool/cache/pipenv|invoke|invoke|0700|tree|yes"
  "/pool/cache/python|invoke|invoke|0700|tree|yes"
  "/pool/cache/python/pycache|invoke|invoke|0700|tree|yes"
  "/pool/cache/pypoetry|invoke|invoke|0700|tree|yes"
  "/pool/cache/npm|invoke|invoke|0700|tree|yes"
  "/pool/cache/pnpm|invoke|invoke|0700|tree|yes"
  "/pool/cache/pnpm/store|invoke|invoke|0700|tree|yes"
  "/pool/cache/pnpm/cache|invoke|invoke|0700|tree|yes"
  "/pool/cache/pnpm/state|invoke|invoke|0700|tree|yes"
  "/pool/cache/yarn|invoke|invoke|0700|tree|yes"
  "/pool/cache/uv|invoke|invoke|0700|tree|yes"
  "/pool/cache/maven|invoke|invoke|0700|tree|yes"
  "/pool/cache/maven/repository|invoke|invoke|0700|tree|yes"
  "/pool/cache/gradle|invoke|invoke|0700|tree|yes"
  "/pool/cache/ivy|invoke|invoke|0700|tree|yes"
  "/pool/cache/coursier|invoke|invoke|0700|tree|yes"
  "/pool/cache/nuget|invoke|invoke|0700|tree|yes"
  "/pool/cache/nuget/packages|invoke|invoke|0700|tree|yes"
  "/pool/cache/nuget/http|invoke|invoke|0700|tree|yes"
  "/pool/cache/nuget/plugins-cache|invoke|invoke|0700|tree|yes"
  "/pool/cache/rubygems|invoke|invoke|0700|tree|yes"
  "/pool/cache/bundle|invoke|invoke|0700|tree|yes"
  "/pool/cache/composer|invoke|invoke|0700|tree|yes"
  "/pool/cache/sbt|invoke|invoke|0700|tree|yes"
  "/pool/cache/sbt/boot|invoke|invoke|0700|tree|yes"
)

readonly SYSTEM_REQUIRED_INVOKE_WRITABLE_POOL_ROOTS=(
  "/pool/builds"
  "/pool/cache"
)

readonly SYSTEM_HOME_DIR_SPECS=(
  ".config|0750|tree|no"
  ".config/system|0750|tree|no"
  ".config/system/profile.d|0750|tree|no"
  ".config/pip|0750|tree|yes"
  ".config/pnpm|0750|tree|yes"
  ".config/pypoetry|0750|tree|yes"
  ".config/bundle|0750|tree|yes"
  ".local|0750|tree|no"
  ".local/bin|0750|dir|no"
  ".local/lib|0750|tree|yes"
  ".local/pipx|0750|tree|yes"
  ".local/share|0750|tree|no"
  ".local/share/keyrings|0700|tree|no"
  ".local/share/man|0750|tree|yes"
  ".local/share/virtualenvs|0700|tree|yes"
  ".local/state|0700|tree|no"
  ".cache|0700|tree|yes"
  ".cargo|0700|tree|yes"
  ".rustup|0700|tree|yes"
  ".npm|0700|tree|yes"
  ".node_modules|0700|tree|yes"
  ".yarn|0700|tree|yes"
  ".gradle|0700|tree|yes"
  ".m2|0700|tree|yes"
  ".maven|0700|tree|yes"
  ".ivy2|0700|tree|yes"
  ".nuget|0700|tree|yes"
  ".dotnet|0700|tree|yes"
  ".bundle|0700|tree|yes"
  ".composer|0700|tree|yes"
  "go|0750|tree|yes"
  ".ssh|0700|tree|no"
  ".gnupg|0700|tree|no"
  "Desktop|0750|dir|no"
  "Downloads|0750|dir|no"
  "Templates|0750|dir|no"
  "Public|0750|dir|no"
  "Documents|0750|dir|no"
  "Music|0750|dir|no"
  "Pictures|0750|dir|no"
  "Videos|0750|dir|no"
)

resolve_path_principal() {
  local token="$1"

  case "$token" in
    invoke) printf '%s' "$SYSTEM_TARGET_USER" ;;
    root) printf '%s' "root" ;;
    *) die "unsupported path principal token: $token" ;;
  esac
}

normalized_mode_triplet() {
  local mode="${1#0}"

  [[ "$mode" =~ ^[0-7]{3,4}$ ]] || die "unsupported mode: $1"
  printf '%s' "${mode: -3}"
}

mode_grants_owner_directory_mutation() {
  local owner_digit
  owner_digit="$(normalized_mode_triplet "$1")"
  owner_digit="${owner_digit:0:1}"
  (((10#$owner_digit & 3) == 3))
}

validate_required_invoke_writable_pool_roots() {
  local required_path spec path owner_token group_token mode scope nocow matched

  for required_path in "${SYSTEM_REQUIRED_INVOKE_WRITABLE_POOL_ROOTS[@]}"; do
    matched="no"
    for spec in "${SYSTEM_POOL_PATH_SPECS[@]}"; do
      IFS='|' read -r path owner_token group_token mode scope nocow <<<"$spec"
      [[ "$path" == "$required_path" ]] || continue
      matched="yes"
      [[ "$owner_token" == "invoke" ]] || die "$required_path must stay owned by the invoking user"
      [[ "$group_token" == "invoke" ]] || die "$required_path must stay grouped to the invoking user"
      mode_grants_owner_directory_mutation "$mode" || {
        die "$required_path must keep owner write and execute permissions"
      }
      break
    done
    [[ "$matched" == "yes" ]] || die "missing required pool permission spec for $required_path"
  done
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

path_fs_type() {
  findmnt -no FSTYPE --target "$1"
}

apply_nocow_attribute() {
  local path="$1"
  local fs_type attrs

  require_dir "$path"
  fs_type="$(path_fs_type "$path" 2>/dev/null || true)"
  [[ "$fs_type" == "btrfs" ]] || die "nodatacow path must be on btrfs: $path (found '${fs_type:-unknown}')"
  attrs="$(lsattr -d "$path" 2>/dev/null | awk '{print $1}')"
  if [[ "$attrs" == *C* ]]; then
    return 0
  fi
  run_cmd chattr +C "$path"
}

repair_tree_ownership() {
  local path="$1"

  [[ -e "$path" ]] || return 0
  run_cmd find -P "$path" -xdev -exec chown -h "$SYSTEM_TARGET_USER:$SYSTEM_TARGET_GROUP" {} +
}

permissions_path_is_nested_under_any() {
  local path="$1"
  local root
  shift || true

  for root in "$@"; do
    [[ "$path" == "$root" || "$path" == "$root/"* ]] && return 0
  done
  return 1
}

apply_system_path_permissions() {
  local spec path owner_token group_token mode owner group scope nocow
  local -a repaired_tree_roots=()

  validate_required_invoke_writable_pool_roots

  for spec in "${SYSTEM_DATA_PATH_SPECS[@]}"; do
    IFS='|' read -r path owner_token group_token mode <<<"$spec"
    owner="$(resolve_path_principal "$owner_token")"
    group="$(resolve_path_principal "$group_token")"
    ensure_directory_state "$path" "$owner" "$group" "$mode"
  done

  for spec in "${SYSTEM_POOL_PATH_SPECS[@]}"; do
    IFS='|' read -r path owner_token group_token mode scope nocow <<<"$spec"
    owner="$(resolve_path_principal "$owner_token")"
    group="$(resolve_path_principal "$group_token")"
    ensure_directory_state "$path" "$owner" "$group" "$mode"
    if [[ "$scope" == "tree" ]]; then
      if ! permissions_path_is_nested_under_any "$path" "${repaired_tree_roots[@]}"; then
        repair_tree_ownership "$path"
        repaired_tree_roots+=("$path")
      fi
    fi
    if [[ "$nocow" == "yes" ]]; then
      apply_nocow_attribute "$path"
    fi
  done
}

apply_home_permissions() {
  local spec relative_path mode scope nocow path
  local -a repaired_tree_roots=()

  ensure_directory_state "$SYSTEM_TARGET_HOME" "$SYSTEM_TARGET_USER" "$SYSTEM_TARGET_GROUP" "$SYSTEM_HOME_MODE"

  for spec in "${SYSTEM_HOME_DIR_SPECS[@]}"; do
    IFS='|' read -r relative_path mode scope nocow <<<"$spec"
    path="$SYSTEM_TARGET_HOME/$relative_path"
    ensure_directory_state "$path" "$SYSTEM_TARGET_USER" "$SYSTEM_TARGET_GROUP" "$mode"
    if [[ "$scope" == "tree" ]]; then
      if permissions_path_is_nested_under_any "$path" "${repaired_tree_roots[@]}"; then
        continue
      fi
      repair_tree_ownership "$path"
      repaired_tree_roots+=("$path")
    fi
    if [[ "$nocow" == "yes" ]]; then
      apply_nocow_attribute "$path"
    fi
  done
}
