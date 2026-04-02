#!/usr/bin/env bash

if ! declare -F retry_cmd >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/apt.sh"
fi

readonly DBUS_BROKER_SESSION_SERVICE_ALIAS_DIR="/usr/local/share/dbus-1/services"

github_api_json() {
  local url="$1"
  retry_cmd 3 curl --fail --location --max-time 30 --silent --show-error "$url"
}

github_json_field() {
  local json_input="$1"
  local python_code="$2"
  printf '%s' "$json_input" | python3 -c "$python_code" 2>/dev/null || true
}

init_broker_runtime_paths() {
  local tarball_name
  tarball_name="$(basename -- "$DBUS_BROKER_TARBALL_URL")"
  require_safe_token "tarball filename" "$tarball_name"

  DBUS_BROKER_CACHE_TARBALL="${DBUS_BROKER_TMP_DIR%/}/$tarball_name"
  DBUS_BROKER_EXTRACT_DIR="${DBUS_BROKER_STATE_DIR%/}/extract"
  DBUS_BROKER_BACKUP_DIR="${DBUS_BROKER_STATE_DIR%/}/backups"
  DBUS_BROKER_RELEASE_PROVENANCE_PATH="${DBUS_BROKER_INSTALL_SHARE_DIR%/}/release.env"
}

validate_env_settings() {
  require_https_url "DBUS_BROKER_TARBALL_URL" "$DBUS_BROKER_TARBALL_URL"
  require_safe_token "DBUS_BROKER_TAG" "$DBUS_BROKER_TAG"
  require_sha256_hex "$DBUS_BROKER_TARBALL_SHA256"
  require_commit_sha "$DBUS_BROKER_COMMIT_SHA"

  require_absolute_path "DBUS_BROKER_INSTALL_BIN_DIR" "$DBUS_BROKER_INSTALL_BIN_DIR"
  require_absolute_path "DBUS_BROKER_INSTALL_MAN_DIR" "$DBUS_BROKER_INSTALL_MAN_DIR"
  require_absolute_path "DBUS_BROKER_INSTALL_SHARE_DIR" "$DBUS_BROKER_INSTALL_SHARE_DIR"
  require_absolute_path "DBUS_BROKER_INSTALL_CATALOG_DIR" "$DBUS_BROKER_INSTALL_CATALOG_DIR"
  require_absolute_path "DBUS_BROKER_SYSTEM_UNIT_PATH" "$DBUS_BROKER_SYSTEM_UNIT_PATH"
  require_absolute_path "DBUS_BROKER_USER_UNIT_PATH" "$DBUS_BROKER_USER_UNIT_PATH"
  require_absolute_path "DBUS_BROKER_STATE_DIR" "$DBUS_BROKER_STATE_DIR"
  require_absolute_path "DBUS_BROKER_TMP_DIR" "$DBUS_BROKER_TMP_DIR"

  require_path_prefix "DBUS_BROKER_INSTALL_BIN_DIR" "$DBUS_BROKER_INSTALL_BIN_DIR" "/usr"
  require_path_prefix "DBUS_BROKER_INSTALL_MAN_DIR" "$DBUS_BROKER_INSTALL_MAN_DIR" "/usr"
  require_path_prefix "DBUS_BROKER_INSTALL_SHARE_DIR" "$DBUS_BROKER_INSTALL_SHARE_DIR" "/usr"
  require_path_prefix "DBUS_BROKER_INSTALL_CATALOG_DIR" "$DBUS_BROKER_INSTALL_CATALOG_DIR" "/etc/systemd"
  require_path_prefix "DBUS_BROKER_SYSTEM_UNIT_PATH" "$DBUS_BROKER_SYSTEM_UNIT_PATH" "/etc/systemd/system"
  require_path_prefix "DBUS_BROKER_USER_UNIT_PATH" "$DBUS_BROKER_USER_UNIT_PATH" "/etc/systemd/user"
  require_path_prefix "DBUS_BROKER_STATE_DIR" "$DBUS_BROKER_STATE_DIR" "/var/lib"
  require_path_prefix "DBUS_BROKER_TMP_DIR" "$DBUS_BROKER_TMP_DIR" "/tmp"

  [[ "$DBUS_BROKER_TARBALL_URL" == *.tar.gz ]] || die "DBUS_BROKER_TARBALL_URL must point to a .tar.gz asset"
  [[ "$DBUS_BROKER_TARBALL_URL" == *"/${DBUS_BROKER_TAG}/"* ]] || die "DBUS_BROKER_TARBALL_URL must include DBUS_BROKER_TAG in release path"
  [[ "$DBUS_BROKER_INSTALL_BIN_DIR" == "/usr/bin" ]] || die "DBUS_BROKER_INSTALL_BIN_DIR must be '/usr/bin' because this compiled dbus-broker-launch executes /usr/bin/dbus-broker"
  [[ "$DBUS_BROKER_INSTALL_MAN_DIR" == "/usr/share/man/man1" ]] || die "DBUS_BROKER_INSTALL_MAN_DIR must be '/usr/share/man/man1' for this managed layout"
  [[ "$DBUS_BROKER_INSTALL_SHARE_DIR" == "/usr/share/dbus-broker" ]] || die "DBUS_BROKER_INSTALL_SHARE_DIR must be '/usr/share/dbus-broker' for this managed layout"
  [[ "$(basename -- "$DBUS_BROKER_SYSTEM_UNIT_PATH")" == "dbus.service" ]] || die "DBUS_BROKER_SYSTEM_UNIT_PATH must target dbus.service"
  [[ "$(basename -- "$DBUS_BROKER_USER_UNIT_PATH")" == "dbus.service" ]] || die "DBUS_BROKER_USER_UNIT_PATH must target dbus.service"

  init_broker_runtime_paths
}

write_root_file() {
  local destination="$1"
  local mode="$2"
  local content="$3"
  run_cmd install -D -m "$mode" /dev/null "$destination"
  printf '%s' "$content" >"$destination"
  run_cmd chmod "$mode" "$destination"
}

ensure_runtime_directories() {
  run_cmd install -d -m 0755 "$DBUS_BROKER_STATE_DIR"
  run_cmd install -d -m 0755 "$DBUS_BROKER_EXTRACT_DIR"
  run_cmd install -d -m 0700 "$DBUS_BROKER_BACKUP_DIR"
}

backup_key_for_path() {
  local path="$1"
  printf '%s' "$path" | sha256sum | awk '{print $1}'
}

backup_meta_path_for_key() {
  local key="$1"
  printf '%s\n' "${DBUS_BROKER_BACKUP_DIR%/}/${key}.path"
}

backup_payload_path_for_key() {
  local key="$1"
  printf '%s\n' "${DBUS_BROKER_BACKUP_DIR%/}/${key}.payload"
}

backup_exists_for_path() {
  local path="$1"
  local key meta
  key="$(backup_key_for_path "$path")"
  meta="$(backup_meta_path_for_key "$key")"
  [[ -f "$meta" ]] || return 1
  [[ "$(cat "$meta")" == "$path" ]] || return 1
  return 0
}

backup_existing_path() {
  local path="$1"
  local key meta payload

  [[ -e "$path" || -L "$path" ]] || return 0
  backup_exists_for_path "$path" && return 0

  key="$(backup_key_for_path "$path")"
  meta="$(backup_meta_path_for_key "$key")"
  payload="$(backup_payload_path_for_key "$key")"

  run_cmd install -d -m 0700 "$DBUS_BROKER_BACKUP_DIR"
  printf '%s' "$path" >"$meta"
  run_cmd chmod 0600 "$meta"
  run_cmd cp -a -- "$path" "$payload"
}

restore_backed_up_path() {
  local path="$1"
  local key meta payload
  key="$(backup_key_for_path "$path")"
  meta="$(backup_meta_path_for_key "$key")"
  payload="$(backup_payload_path_for_key "$key")"

  [[ -f "$meta" ]] || return 1
  [[ -e "$payload" || -L "$payload" ]] || return 1
  [[ "$(cat "$meta")" == "$path" ]] || return 1

  run_cmd rm -rf -- "$path"
  run_cmd cp -a -- "$payload" "$path"
  run_cmd rm -f -- "$meta" "$payload"
  return 0
}

install_managed_file() {
  local mode="$1"
  local source="$2"
  local destination="$3"
  backup_existing_path "$destination"
  run_cmd install -m "$mode" "$source" "$destination"
}

dbus_service_alias_path() {
  printf '%s/%s\n' "$DBUS_BROKER_SESSION_SERVICE_ALIAS_DIR" "$1"
}

install_session_service_alias() {
  local alias_name="$1"
  local source_path="$2"
  local alias_path

  [[ -f "$source_path" ]] || {
    log_warn "skipping optional D-Bus service alias '$alias_name' because source is missing: $source_path"
    return 0
  }

  alias_path="$(dbus_service_alias_path "$alias_name")"
  backup_existing_path "$alias_path"
  run_cmd install -d -m 0755 "$DBUS_BROKER_SESSION_SERVICE_ALIAS_DIR"
  run_cmd ln -sfn "$source_path" "$alias_path"
}

install_session_service_aliases() {
  install_session_service_alias "org.freedesktop.Notifications.service" "/usr/share/dbus-1/services/fr.emersion.mako.service"
  install_session_service_alias "org.freedesktop.FileManager1.service" "/usr/share/dbus-1/services/org.xfce.Thunar.FileManager1.service"
  install_session_service_alias "org.freedesktop.thumbnails.Cache1.service" "/usr/share/dbus-1/services/org.xfce.Tumbler.Cache1.service"
  install_session_service_alias "org.freedesktop.thumbnails.Manager1.service" "/usr/share/dbus-1/services/org.xfce.Tumbler.Manager1.service"
  install_session_service_alias "org.freedesktop.thumbnails.Thumbnailer1.service" "/usr/share/dbus-1/services/org.xfce.Tumbler.Thumbnailer1.service"
}

verify_release_tag_commit() {
  local owner repo ref_api tag_api release_api release_json ref_json tag_json asset_name digest
  local object_type object_sha ref_commit tag_depth
  owner="$(printf '%s' "$DBUS_BROKER_TARBALL_URL" | awk -F/ '{print $4}')"
  repo="$(printf '%s' "$DBUS_BROKER_TARBALL_URL" | awk -F/ '{print $5}')"
  [[ -n "$owner" && -n "$repo" ]] || die "could not derive github owner/repo from DBUS_BROKER_TARBALL_URL"

  ref_api="https://api.github.com/repos/${owner}/${repo}/git/ref/tags/${DBUS_BROKER_TAG}"
  release_api="https://api.github.com/repos/${owner}/${repo}/releases/tags/${DBUS_BROKER_TAG}"
  ref_json="$(github_api_json "$ref_api")" || die "failed to resolve git tag ref from GitHub API"
  release_json="$(github_api_json "$release_api")" || die "failed to resolve release metadata from GitHub API"

  object_type="$(github_json_field "$ref_json" 'import json,sys; print(json.load(sys.stdin)["object"]["type"])')"
  object_sha="$(github_json_field "$ref_json" 'import json,sys; print(json.load(sys.stdin)["object"]["sha"])')"
  [[ -n "$object_type" && -n "$object_sha" ]] || die "could not parse git tag object from GitHub API response"

  ref_commit="$object_sha"
  tag_depth=0
  while [[ "$object_type" == "tag" ]]; do
    tag_api="https://api.github.com/repos/${owner}/${repo}/git/tags/${object_sha}"
    tag_json="$(github_api_json "$tag_api")" || die "failed to resolve annotated git tag object from GitHub API"
    object_type="$(github_json_field "$tag_json" 'import json,sys; print(json.load(sys.stdin)["object"]["type"])')"
    object_sha="$(github_json_field "$tag_json" 'import json,sys; print(json.load(sys.stdin)["object"]["sha"])')"
    [[ -n "$object_type" && -n "$object_sha" ]] || die "could not parse annotated git tag object from GitHub API response"
    ref_commit="$object_sha"
    tag_depth=$((tag_depth + 1))
    ((tag_depth <= 4)) || die "git tag resolution exceeded maximum depth while resolving '$DBUS_BROKER_TAG'"
  done

  [[ "$object_type" == "commit" ]] || die "git tag '$DBUS_BROKER_TAG' did not resolve to a commit object, found '$object_type'"
  [[ "$ref_commit" == "$DBUS_BROKER_COMMIT_SHA" ]] || die "tag commit mismatch: expected '$DBUS_BROKER_COMMIT_SHA', got '$ref_commit'"

  asset_name="$(basename -- "$DBUS_BROKER_TARBALL_URL")"
  digest="$(printf '%s' "$release_json" | python3 -c 'import json,sys; data=json.load(sys.stdin); asset_name=sys.argv[1]; assets=data.get("assets",[]); matched=[a for a in assets if a.get("name")==asset_name]; print((matched[0].get("digest","") if matched else ""))' "$asset_name" 2>/dev/null || true)"
  [[ -n "$digest" ]] || die "release asset '$asset_name' not found in GitHub release metadata"
  [[ "$digest" == "sha256:${DBUS_BROKER_TARBALL_SHA256}" ]] || die "release digest mismatch for '$asset_name': expected 'sha256:${DBUS_BROKER_TARBALL_SHA256}', got '$digest'"
}

download_release_tarball() {
  run_cmd install -d -m 0755 "$DBUS_BROKER_TMP_DIR"
  retry_cmd 3 curl --fail --location --max-time 180 --silent --show-error \
    --output "$DBUS_BROKER_CACHE_TARBALL" "$DBUS_BROKER_TARBALL_URL" || die "failed to download compiled dbus-broker tarball"
}

verify_release_tarball_sha() {
  local actual_sha
  require_file "$DBUS_BROKER_CACHE_TARBALL"
  actual_sha="$(sha256sum "$DBUS_BROKER_CACHE_TARBALL" | awk '{print $1}')"
  [[ "$actual_sha" == "$DBUS_BROKER_TARBALL_SHA256" ]] || die "tarball sha mismatch: expected '$DBUS_BROKER_TARBALL_SHA256', got '$actual_sha'"
}

verify_tarball_manifest() {
  local entry
  local -a expected_entries=(
    "./"
    "./usr/"
    "./usr/bin/"
    "./usr/bin/dbus-broker"
    "./usr/bin/dbus-broker-launch"
    "./usr/bin/dbus-broker-session"
    "./usr/lib/"
    "./usr/lib/systemd/"
    "./usr/lib/systemd/catalog/"
    "./usr/lib/systemd/catalog/dbus-broker-launch.catalog"
    "./usr/lib/systemd/catalog/dbus-broker.catalog"
    "./usr/lib/systemd/system/"
    "./usr/lib/systemd/system/dbus-broker.service"
    "./usr/lib/systemd/user/"
    "./usr/lib/systemd/user/dbus-broker.service"
    "./usr/share/"
    "./usr/share/dbus-broker/"
    "./usr/share/dbus-broker/release-verification.txt"
    "./usr/share/dbus-broker/subprojects.lock"
    "./usr/share/man/"
    "./usr/share/man/man1/"
    "./usr/share/man/man1/dbus-broker-launch.1"
    "./usr/share/man/man1/dbus-broker.1"
  )
  local expected_text

  expected_text="$(printf '%s\n' "${expected_entries[@]}")"
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    [[ "$entry" == ./* ]] || die "tarball entry must stay relative, found '$entry'"
    [[ "$entry" != */../* && "$entry" != ../* && "$entry" != */.. && "$entry" != *"/./"* ]] || die "tarball entry contains traversal segments: '$entry'"
    printf '%s\n' "$expected_text" | grep -Fx -- "$entry" >/dev/null || die "unexpected tarball entry: '$entry'"
  done < <(tar -tf "$DBUS_BROKER_CACHE_TARBALL")
}

extract_release_tarball() {
  run_cmd rm -rf -- "$DBUS_BROKER_EXTRACT_DIR"
  run_cmd install -d -m 0755 "$DBUS_BROKER_EXTRACT_DIR"
  run_cmd tar -xf "$DBUS_BROKER_CACHE_TARBALL" -C "$DBUS_BROKER_EXTRACT_DIR" --no-same-owner --no-same-permissions
}

require_release_layout() {
  local -a required_paths=(
    "$DBUS_BROKER_EXTRACT_DIR/usr/bin/dbus-broker"
    "$DBUS_BROKER_EXTRACT_DIR/usr/bin/dbus-broker-launch"
    "$DBUS_BROKER_EXTRACT_DIR/usr/bin/dbus-broker-session"
    "$DBUS_BROKER_EXTRACT_DIR/usr/lib/systemd/system/dbus-broker.service"
    "$DBUS_BROKER_EXTRACT_DIR/usr/lib/systemd/user/dbus-broker.service"
    "$DBUS_BROKER_EXTRACT_DIR/usr/lib/systemd/catalog/dbus-broker.catalog"
    "$DBUS_BROKER_EXTRACT_DIR/usr/lib/systemd/catalog/dbus-broker-launch.catalog"
    "$DBUS_BROKER_EXTRACT_DIR/usr/share/man/man1/dbus-broker.1"
    "$DBUS_BROKER_EXTRACT_DIR/usr/share/man/man1/dbus-broker-launch.1"
    "$DBUS_BROKER_EXTRACT_DIR/usr/share/dbus-broker/release-verification.txt"
    "$DBUS_BROKER_EXTRACT_DIR/usr/share/dbus-broker/subprojects.lock"
  )
  local path
  for path in "${required_paths[@]}"; do
    require_file "$path"
  done
}

prepare_release_payload() {
  verify_release_tag_commit
  ensure_runtime_directories
  download_release_tarball
  verify_release_tarball_sha
  verify_tarball_manifest
  extract_release_tarball
  require_release_layout
  log_info "release payload prepared at '$DBUS_BROKER_EXTRACT_DIR'"
}

install_release_payload() {
  run_cmd install -d -m 0755 "$DBUS_BROKER_INSTALL_BIN_DIR"
  run_cmd install -d -m 0755 "$DBUS_BROKER_INSTALL_MAN_DIR"
  run_cmd install -d -m 0755 "$DBUS_BROKER_INSTALL_SHARE_DIR"
  run_cmd install -d -m 0755 "$DBUS_BROKER_INSTALL_CATALOG_DIR"

  install_managed_file 0755 "$DBUS_BROKER_EXTRACT_DIR/usr/bin/dbus-broker" "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker"
  install_managed_file 0755 "$DBUS_BROKER_EXTRACT_DIR/usr/bin/dbus-broker-launch" "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker-launch"
  install_managed_file 0755 "$DBUS_BROKER_EXTRACT_DIR/usr/bin/dbus-broker-session" "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker-session"

  install_managed_file 0644 "$DBUS_BROKER_EXTRACT_DIR/usr/share/man/man1/dbus-broker.1" "$DBUS_BROKER_INSTALL_MAN_DIR/dbus-broker.1"
  install_managed_file 0644 "$DBUS_BROKER_EXTRACT_DIR/usr/share/man/man1/dbus-broker-launch.1" "$DBUS_BROKER_INSTALL_MAN_DIR/dbus-broker-launch.1"

  install_managed_file 0644 "$DBUS_BROKER_EXTRACT_DIR/usr/share/dbus-broker/release-verification.txt" "$DBUS_BROKER_INSTALL_SHARE_DIR/release-verification.txt"
  install_managed_file 0644 "$DBUS_BROKER_EXTRACT_DIR/usr/share/dbus-broker/subprojects.lock" "$DBUS_BROKER_INSTALL_SHARE_DIR/subprojects.lock"
  install_managed_file 0644 "$DBUS_BROKER_EXTRACT_DIR/usr/lib/systemd/catalog/dbus-broker.catalog" "$DBUS_BROKER_INSTALL_CATALOG_DIR/dbus-broker.catalog"
  install_managed_file 0644 "$DBUS_BROKER_EXTRACT_DIR/usr/lib/systemd/catalog/dbus-broker-launch.catalog" "$DBUS_BROKER_INSTALL_CATALOG_DIR/dbus-broker-launch.catalog"

  local provenance
  provenance="$(cat <<EOF
DBUS_BROKER_TAG="$DBUS_BROKER_TAG"
DBUS_BROKER_COMMIT_SHA="$DBUS_BROKER_COMMIT_SHA"
DBUS_BROKER_TARBALL_SHA256="$DBUS_BROKER_TARBALL_SHA256"
DBUS_BROKER_TARBALL_URL="$DBUS_BROKER_TARBALL_URL"
DBUS_BROKER_INSTALLED_AT_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
EOF
)"
  backup_existing_path "$DBUS_BROKER_RELEASE_PROVENANCE_PATH"
  write_root_file "$DBUS_BROKER_RELEASE_PROVENANCE_PATH" 0644 "$provenance"

  run_cmd journalctl --update-catalog >/dev/null 2>&1 || true
}

strip_install_section() {
  local source="$1"
  awk '
    /^\[Install\]/ { in_install=1; next }
    !in_install { print }
  ' "$source"
}

render_system_bus_unit() {
  local source unit_content
  source="$DBUS_BROKER_EXTRACT_DIR/usr/lib/systemd/system/dbus-broker.service"
  unit_content="$(
    strip_install_section "$source" | sed "s#^ExecStart=.*#ExecStart=${DBUS_BROKER_INSTALL_BIN_DIR}/dbus-broker-launch --scope system#"
  )"
  backup_existing_path "$DBUS_BROKER_SYSTEM_UNIT_PATH"
  write_root_file "$DBUS_BROKER_SYSTEM_UNIT_PATH" 0644 "$unit_content"
}

render_user_bus_unit() {
  local source unit_content
  source="$DBUS_BROKER_EXTRACT_DIR/usr/lib/systemd/user/dbus-broker.service"
  unit_content="$(
    strip_install_section "$source" | sed "s#^ExecStart=.*#ExecStart=${DBUS_BROKER_INSTALL_BIN_DIR}/dbus-broker-launch --scope user#"
  )"
  backup_existing_path "$DBUS_BROKER_USER_UNIT_PATH"
  write_root_file "$DBUS_BROKER_USER_UNIT_PATH" 0644 "$unit_content"
}

render_managed_units() {
  render_system_bus_unit
  render_user_bus_unit
  install_session_service_aliases
}

reload_user_manager_if_reachable() {
  if runuser -u "$DBUS_BROKER_TARGET_USER" -- systemctl --user daemon-reload >/dev/null 2>&1; then
    return 0
  fi
  log_warn "user systemd manager is not reachable for '$DBUS_BROKER_TARGET_USER'; managed user dbus.service will apply on next login"
}

enable_broker_runtime() {
  local system_fragment
  require_file "$DBUS_BROKER_SYSTEM_UNIT_PATH"
  require_file "$DBUS_BROKER_USER_UNIT_PATH"
  require_file "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker-launch"
  require_file "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker"

  install_session_service_aliases
  run_cmd systemctl daemon-reload
  reload_user_manager_if_reachable
  system_fragment="$(systemctl show -p FragmentPath --value dbus.service 2>/dev/null || true)"
  [[ "$system_fragment" == "$DBUS_BROKER_SYSTEM_UNIT_PATH" ]] || die "system dbus.service fragment is not the managed override: '$system_fragment'"
  log_info "managed dbus.service overrides are staged; reboot or a later controlled dbus.service restart will activate dbus-broker"
}

remove_if_present() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    run_cmd rm -rf -- "$path"
  fi
}

path_owned_by_package() {
  local path="$1"
  dpkg-query -S -- "$path" >/dev/null 2>&1
}

remove_unmanaged_artifact() {
  local path="$1"
  if path_owned_by_package "$path"; then
    log_warn "keeping package-owned path: $path"
    return 0
  fi
  remove_if_present "$path"
}

remove_broker_install() {
  local fallback_fragment
  local alias_path

  restore_backed_up_path "$DBUS_BROKER_SYSTEM_UNIT_PATH" || remove_if_present "$DBUS_BROKER_SYSTEM_UNIT_PATH"
  restore_backed_up_path "$DBUS_BROKER_USER_UNIT_PATH" || remove_if_present "$DBUS_BROKER_USER_UNIT_PATH"
  restore_backed_up_path "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker" || remove_unmanaged_artifact "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker"
  restore_backed_up_path "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker-launch" || remove_unmanaged_artifact "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker-launch"
  restore_backed_up_path "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker-session" || remove_unmanaged_artifact "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker-session"
  restore_backed_up_path "$DBUS_BROKER_INSTALL_MAN_DIR/dbus-broker.1" || remove_unmanaged_artifact "$DBUS_BROKER_INSTALL_MAN_DIR/dbus-broker.1"
  restore_backed_up_path "$DBUS_BROKER_INSTALL_MAN_DIR/dbus-broker-launch.1" || remove_unmanaged_artifact "$DBUS_BROKER_INSTALL_MAN_DIR/dbus-broker-launch.1"
  restore_backed_up_path "$DBUS_BROKER_INSTALL_SHARE_DIR/release-verification.txt" || remove_unmanaged_artifact "$DBUS_BROKER_INSTALL_SHARE_DIR/release-verification.txt"
  restore_backed_up_path "$DBUS_BROKER_INSTALL_SHARE_DIR/subprojects.lock" || remove_unmanaged_artifact "$DBUS_BROKER_INSTALL_SHARE_DIR/subprojects.lock"
  restore_backed_up_path "$DBUS_BROKER_RELEASE_PROVENANCE_PATH" || remove_unmanaged_artifact "$DBUS_BROKER_RELEASE_PROVENANCE_PATH"
  restore_backed_up_path "$DBUS_BROKER_INSTALL_CATALOG_DIR/dbus-broker.catalog" || remove_unmanaged_artifact "$DBUS_BROKER_INSTALL_CATALOG_DIR/dbus-broker.catalog"
  restore_backed_up_path "$DBUS_BROKER_INSTALL_CATALOG_DIR/dbus-broker-launch.catalog" || remove_unmanaged_artifact "$DBUS_BROKER_INSTALL_CATALOG_DIR/dbus-broker-launch.catalog"
  while IFS= read -r alias_path; do
    [[ -n "$alias_path" ]] || continue
    restore_backed_up_path "$alias_path" || remove_unmanaged_artifact "$alias_path"
  done < <(printf '%s\n' \
    "$(dbus_service_alias_path "org.freedesktop.Notifications.service")" \
    "$(dbus_service_alias_path "org.freedesktop.FileManager1.service")" \
    "$(dbus_service_alias_path "org.freedesktop.thumbnails.Cache1.service")" \
    "$(dbus_service_alias_path "org.freedesktop.thumbnails.Manager1.service")" \
    "$(dbus_service_alias_path "org.freedesktop.thumbnails.Thumbnailer1.service")")
  remove_if_present "$DBUS_BROKER_CACHE_TARBALL"
  remove_if_present "$DBUS_BROKER_EXTRACT_DIR"
  remove_if_present "$DBUS_BROKER_BACKUP_DIR"
  run_cmd rmdir --ignore-fail-on-non-empty "$DBUS_BROKER_STATE_DIR" >/dev/null 2>&1 || true

  run_cmd systemctl daemon-reload
  reload_user_manager_if_reachable
  fallback_fragment="$(systemctl show -p FragmentPath --value dbus.service 2>/dev/null || true)"
  [[ -n "$fallback_fragment" && -f "$fallback_fragment" ]] || die "no fallback dbus.service fragment is available after removing managed override"
  run_cmd journalctl --update-catalog >/dev/null 2>&1 || true
  log_info "managed dbus-broker overrides removed; fallback dbus.service units are staged for next reboot/login or a later controlled dbus.service restart"
}

print_env_redacted() {
  local env_file="$1"
  sed -n '1,260p' "$env_file"
}
