#!/usr/bin/env bash

if ! declare -F retry_cmd >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/apt.sh"
fi

readonly DBUS_BROKER_SESSION_SERVICE_ALIAS_DIR="/usr/local/share/dbus-1/services"

init_broker_runtime_paths() {
  DBUS_BROKER_BACKUP_DIR="${DBUS_BROKER_STATE_DIR%/}/backups"
  DBUS_BROKER_CARGO_HOME="${DBUS_BROKER_STATE_DIR%/}/cargo"
  DBUS_BROKER_RUSTUP_HOME="${DBUS_BROKER_STATE_DIR%/}/rustup"
  DBUS_BROKER_LEGACY_PROVENANCE_PATH="${DBUS_BROKER_INSTALL_SHARE_DIR%/}/release.env"
  DBUS_BROKER_LEGACY_VERIFICATION_PATH="${DBUS_BROKER_INSTALL_SHARE_DIR%/}/release-verification.txt"
  DBUS_BROKER_BUILD_PROVENANCE_PATH="${DBUS_BROKER_INSTALL_SHARE_DIR%/}/source-build.env"
  DBUS_BROKER_BUILD_VERIFICATION_PATH="${DBUS_BROKER_INSTALL_SHARE_DIR%/}/source-build-verification.txt"
  DBUS_BROKER_SUBPROJECTS_LOCK_INSTALL_PATH="${DBUS_BROKER_INSTALL_SHARE_DIR%/}/subprojects.lock"
  DBUS_BROKER_WORK_ROOT=""
  DBUS_BROKER_REPO_DIR=""
  DBUS_BROKER_BUILD_DIR=""
  DBUS_BROKER_STAGE_DIR=""
  DBUS_BROKER_SUBPROJECTS_LOCK_PATH=""
}

validate_env_settings() {
  require_https_url "DBUS_BROKER_GIT_URL" "$DBUS_BROKER_GIT_URL"
  require_commit_sha "$DBUS_BROKER_COMMIT_SHA"
  [[ "$DBUS_BROKER_RUST_TOOLCHAIN" =~ ^nightly-[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || {
    die "DBUS_BROKER_RUST_TOOLCHAIN must be a dated nightly, found '$DBUS_BROKER_RUST_TOOLCHAIN'"
  }

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

  [[ "$DBUS_BROKER_INSTALL_BIN_DIR" == "/usr/bin" ]] || die "DBUS_BROKER_INSTALL_BIN_DIR must be '/usr/bin'"
  [[ "$DBUS_BROKER_INSTALL_MAN_DIR" == "/usr/share/man/man1" ]] || die "DBUS_BROKER_INSTALL_MAN_DIR must be '/usr/share/man/man1'"
  [[ "$DBUS_BROKER_INSTALL_SHARE_DIR" == "/usr/share/dbus-broker" ]] || die "DBUS_BROKER_INSTALL_SHARE_DIR must be '/usr/share/dbus-broker'"
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
  run_cmd install -d -m 0700 "$DBUS_BROKER_BACKUP_DIR"
  run_cmd install -d -m 0755 "$DBUS_BROKER_INSTALL_SHARE_DIR"
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

normalize_git_url() {
  local url="$1"
  url="${url%/}"
  url="${url%.git}"
  printf '%s\n' "$url"
}

verify_checkout_remote() {
  local repo_dir="$1"
  local expected_url="$2"
  local actual_url

  actual_url="$(git -C "$repo_dir" remote get-url origin)"
  [[ "$(normalize_git_url "$actual_url")" == "$(normalize_git_url "$expected_url")" ]] || {
    die "unexpected git remote for $repo_dir: expected '$expected_url', got '$actual_url'"
  }
}

apply_patch_series_if_present() {
  local repo_dir="$1"
  local series_path="$repo_dir/patches/release/series"
  local series_entry patch_path

  [[ -f "$series_path" ]] || return 0

  while IFS= read -r series_entry; do
    series_entry="${series_entry%%#*}"
    series_entry="${series_entry#"${series_entry%%[![:space:]]*}"}"
    series_entry="${series_entry%"${series_entry##*[![:space:]]}"}"
    [[ -n "$series_entry" ]] || continue

    patch_path="$repo_dir/$series_entry"
    if [[ ! -f "$patch_path" ]]; then
      patch_path="$repo_dir/patches/release/$series_entry"
    fi
    [[ -f "$patch_path" ]] || die "missing release patch referenced by $series_path: $series_entry"

    if git -C "$repo_dir" apply --check "$patch_path" >/dev/null 2>&1; then
      run_cmd git -C "$repo_dir" apply "$patch_path"
      continue
    fi

    git -C "$repo_dir" apply --reverse --check "$patch_path" >/dev/null 2>&1 || {
      die "release patch '$series_entry' is neither applicable nor already applied in $repo_dir"
    }
  done <"$series_path"
}

ensure_rustup_toolchain() {
  local toolchain="$1"
  local rustup_bin init_script

  [[ "$toolchain" =~ ^nightly-[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || {
    die "DBUS_BROKER_RUST_TOOLCHAIN must be a dated nightly, found '$toolchain'"
  }

  run_cmd install -d -m 0755 "$DBUS_BROKER_CARGO_HOME" "$DBUS_BROKER_RUSTUP_HOME"
  rustup_bin="$DBUS_BROKER_CARGO_HOME/bin/rustup"

  if [[ ! -x "$rustup_bin" ]]; then
    init_script="$(mktemp "/tmp/dbus-broker-rustup.XXXXXX.sh")"
    retry_cmd 3 curl --fail --location --max-time 180 --silent --show-error \
      -o "$init_script" "https://sh.rustup.rs"
    run_cmd chmod 0755 "$init_script"
    run_cmd env CARGO_HOME="$DBUS_BROKER_CARGO_HOME" RUSTUP_HOME="$DBUS_BROKER_RUSTUP_HOME" sh "$init_script" -y --profile minimal --default-toolchain none
    run_cmd rm -f -- "$init_script"
  fi

  run_cmd env CARGO_HOME="$DBUS_BROKER_CARGO_HOME" RUSTUP_HOME="$DBUS_BROKER_RUSTUP_HOME" "$rustup_bin" toolchain install "$toolchain" --profile minimal
}

run_with_rust_toolchain() {
  env \
    CARGO_HOME="$DBUS_BROKER_CARGO_HOME" \
    RUSTUP_HOME="$DBUS_BROKER_RUSTUP_HOME" \
    PATH="$DBUS_BROKER_CARGO_HOME/bin:$PATH" \
    RUSTUP_TOOLCHAIN="$DBUS_BROKER_RUST_TOOLCHAIN" \
    "$@"
}

dbus_broker_meson_args() {
  cat <<'EOF'
--buildtype=release
--prefix=/usr
--warnlevel=2
-Dapparmor=true
-Daudit=false
-Ddocs=true
-Ddoctest=false
-Dlauncher=true
-Dreference-test=false
-Dselinux=false
-Dtests=false
EOF
}

record_subproject_manifest() {
  local repo_dir="$1"
  local manifest_path="$2"
  local wrap_path subproject_path subproject_name remote revision

  : >"$manifest_path"
  while IFS= read -r wrap_path; do
    [[ -n "$wrap_path" ]] || continue
    subproject_name="$(basename "${wrap_path%.wrap}")"
    subproject_path="$repo_dir/subprojects/$subproject_name"
    if [[ -d "$subproject_path/.git" ]]; then
      remote="$(git -C "$subproject_path" remote get-url origin 2>/dev/null || printf '%s' 'unknown')"
      revision="$(git -C "$subproject_path" rev-parse HEAD 2>/dev/null || printf '%s' 'unknown')"
      printf '%s\t%s\t%s\n' "$subproject_name" "$remote" "$revision" >>"$manifest_path"
    else
      printf '%s\t%s\t%s\n' "$subproject_name" "wrap-only" "$(basename "$wrap_path")" >>"$manifest_path"
    fi
  done < <(find "$repo_dir/subprojects" -maxdepth 1 -type f -name '*.wrap' | LC_ALL=C sort)
}

cleanup_build_workspace() {
  if [[ -n "${DBUS_BROKER_WORK_ROOT:-}" ]]; then
    [[ "$DBUS_BROKER_WORK_ROOT" == /tmp/* ]] || die "refusing to remove unexpected dbus-broker work root: $DBUS_BROKER_WORK_ROOT"
    run_cmd rm -rf -- "$DBUS_BROKER_WORK_ROOT"
  fi
  DBUS_BROKER_WORK_ROOT=""
  DBUS_BROKER_REPO_DIR=""
  DBUS_BROKER_BUILD_DIR=""
  DBUS_BROKER_STAGE_DIR=""
  DBUS_BROKER_SUBPROJECTS_LOCK_PATH=""
}

require_stage_layout() {
  local stage_root="$1"
  local -a required_paths=(
    "$stage_root/usr/bin/dbus-broker"
    "$stage_root/usr/bin/dbus-broker-launch"
    "$stage_root/usr/bin/dbus-broker-session"
    "$stage_root/usr/lib/systemd/system/dbus-broker.service"
    "$stage_root/usr/lib/systemd/user/dbus-broker.service"
    "$stage_root/usr/lib/systemd/catalog/dbus-broker.catalog"
    "$stage_root/usr/lib/systemd/catalog/dbus-broker-launch.catalog"
    "$stage_root/usr/share/man/man1/dbus-broker.1"
    "$stage_root/usr/share/man/man1/dbus-broker-launch.1"
  )
  local path
  for path in "${required_paths[@]}"; do
    require_file "$path"
  done
}

assert_stage_binary_dependencies() {
  local stage_root="$1"
  local binary_path missing_output
  local -a binaries=(
    "$stage_root/usr/bin/dbus-broker"
    "$stage_root/usr/bin/dbus-broker-launch"
    "$stage_root/usr/bin/dbus-broker-session"
  )

  for binary_path in "${binaries[@]}"; do
    missing_output="$(ldd "$binary_path" 2>&1 | awk '/not found/ {print}')"
    [[ -z "$missing_output" ]] || {
      die "staged dbus-broker binary has unresolved shared-library dependencies:
$missing_output"
    }
  done
}

prepare_source_build() {
  local meson_args_file
  local -a meson_args=()

  cleanup_build_workspace
  ensure_runtime_directories
  ensure_rustup_toolchain "$DBUS_BROKER_RUST_TOOLCHAIN"

  DBUS_BROKER_WORK_ROOT="$(mktemp -d "${DBUS_BROKER_TMP_DIR%/}/dbus-broker.XXXXXX")"
  DBUS_BROKER_REPO_DIR="$DBUS_BROKER_WORK_ROOT/source"
  DBUS_BROKER_BUILD_DIR="$DBUS_BROKER_WORK_ROOT/build"
  DBUS_BROKER_STAGE_DIR="$DBUS_BROKER_WORK_ROOT/stage"
  DBUS_BROKER_SUBPROJECTS_LOCK_PATH="$DBUS_BROKER_WORK_ROOT/subprojects.lock"

  retry_cmd 3 git clone --quiet --filter=blob:none "$DBUS_BROKER_GIT_URL" "$DBUS_BROKER_REPO_DIR"
  retry_cmd 3 git -C "$DBUS_BROKER_REPO_DIR" fetch --quiet --depth 1 origin "$DBUS_BROKER_COMMIT_SHA"
  run_cmd git -C "$DBUS_BROKER_REPO_DIR" checkout --quiet --detach "$DBUS_BROKER_COMMIT_SHA"
  verify_checkout_remote "$DBUS_BROKER_REPO_DIR" "$DBUS_BROKER_GIT_URL"
  [[ "$(git -C "$DBUS_BROKER_REPO_DIR" rev-parse HEAD)" == "$DBUS_BROKER_COMMIT_SHA" ]] || {
    die "dbus-broker checkout did not resolve to expected commit '$DBUS_BROKER_COMMIT_SHA'"
  }
  apply_patch_series_if_present "$DBUS_BROKER_REPO_DIR"

  run_with_rust_toolchain bash -lc '
    set -euo pipefail
    cd "$1"
    meson subprojects download
  ' bash "$DBUS_BROKER_REPO_DIR"
  record_subproject_manifest "$DBUS_BROKER_REPO_DIR" "$DBUS_BROKER_SUBPROJECTS_LOCK_PATH"

  meson_args_file="$(mktemp "${DBUS_BROKER_WORK_ROOT%/}/meson-args.XXXXXX")"
  dbus_broker_meson_args | sed '/^[[:space:]]*$/d' >"$meson_args_file"
  while IFS= read -r meson_arg; do
    [[ -n "$meson_arg" ]] || continue
    meson_args+=("$meson_arg")
  done <"$meson_args_file"
  run_cmd rm -f -- "$meson_args_file"

  run_with_rust_toolchain meson setup "$DBUS_BROKER_BUILD_DIR" "$DBUS_BROKER_REPO_DIR" "${meson_args[@]}"
  run_with_rust_toolchain meson compile -C "$DBUS_BROKER_BUILD_DIR"
  run_cmd env DESTDIR="$DBUS_BROKER_STAGE_DIR" meson install -C "$DBUS_BROKER_BUILD_DIR" --no-rebuild
  require_stage_layout "$DBUS_BROKER_STAGE_DIR"
  assert_stage_binary_dependencies "$DBUS_BROKER_STAGE_DIR"
}

install_source_build() {
  local provenance verification

  [[ -n "${DBUS_BROKER_STAGE_DIR:-}" ]] || die "dbus-broker staged tree is not prepared"

  run_cmd install -d -m 0755 "$DBUS_BROKER_INSTALL_BIN_DIR"
  run_cmd install -d -m 0755 "$DBUS_BROKER_INSTALL_MAN_DIR"
  run_cmd install -d -m 0755 "$DBUS_BROKER_INSTALL_SHARE_DIR"
  run_cmd install -d -m 0755 "$DBUS_BROKER_INSTALL_CATALOG_DIR"

  install_managed_file 0755 "$DBUS_BROKER_STAGE_DIR/usr/bin/dbus-broker" "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker"
  install_managed_file 0755 "$DBUS_BROKER_STAGE_DIR/usr/bin/dbus-broker-launch" "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker-launch"
  install_managed_file 0755 "$DBUS_BROKER_STAGE_DIR/usr/bin/dbus-broker-session" "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker-session"

  install_managed_file 0644 "$DBUS_BROKER_STAGE_DIR/usr/share/man/man1/dbus-broker.1" "$DBUS_BROKER_INSTALL_MAN_DIR/dbus-broker.1"
  install_managed_file 0644 "$DBUS_BROKER_STAGE_DIR/usr/share/man/man1/dbus-broker-launch.1" "$DBUS_BROKER_INSTALL_MAN_DIR/dbus-broker-launch.1"
  install_managed_file 0644 "$DBUS_BROKER_STAGE_DIR/usr/lib/systemd/catalog/dbus-broker.catalog" "$DBUS_BROKER_INSTALL_CATALOG_DIR/dbus-broker.catalog"
  install_managed_file 0644 "$DBUS_BROKER_STAGE_DIR/usr/lib/systemd/catalog/dbus-broker-launch.catalog" "$DBUS_BROKER_INSTALL_CATALOG_DIR/dbus-broker-launch.catalog"

  provenance="$(cat <<EOF
DBUS_BROKER_GIT_URL="$DBUS_BROKER_GIT_URL"
DBUS_BROKER_COMMIT_SHA="$DBUS_BROKER_COMMIT_SHA"
DBUS_BROKER_RUST_TOOLCHAIN="$DBUS_BROKER_RUST_TOOLCHAIN"
DBUS_BROKER_RUSTC_VERSION="$(run_with_rust_toolchain rustc --version)"
DBUS_BROKER_CARGO_VERSION="$(run_with_rust_toolchain cargo --version)"
DBUS_BROKER_MESON_VERSION="$(meson --version)"
DBUS_BROKER_BINDGEN_VERSION="$(bindgen --version)"
DBUS_BROKER_INSTALLED_AT_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
EOF
)"
  backup_existing_path "$DBUS_BROKER_BUILD_PROVENANCE_PATH"
  write_root_file "$DBUS_BROKER_BUILD_PROVENANCE_PATH" 0644 "$provenance"
  remove_if_present "$DBUS_BROKER_LEGACY_PROVENANCE_PATH"

  verification="$(cat <<EOF
Build directory: $DBUS_BROKER_BUILD_DIR
Source directory: $DBUS_BROKER_REPO_DIR
Meson args:
$(dbus_broker_meson_args)
EOF
)"
  backup_existing_path "$DBUS_BROKER_BUILD_VERIFICATION_PATH"
  write_root_file "$DBUS_BROKER_BUILD_VERIFICATION_PATH" 0644 "$verification"
  remove_if_present "$DBUS_BROKER_LEGACY_VERIFICATION_PATH"

  backup_existing_path "$DBUS_BROKER_SUBPROJECTS_LOCK_INSTALL_PATH"
  run_cmd install -m 0644 "$DBUS_BROKER_SUBPROJECTS_LOCK_PATH" "$DBUS_BROKER_SUBPROJECTS_LOCK_INSTALL_PATH"
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
  source="$DBUS_BROKER_STAGE_DIR/usr/lib/systemd/system/dbus-broker.service"
  unit_content="$(
    strip_install_section "$source" | sed "s#^ExecStart=.*#ExecStart=${DBUS_BROKER_INSTALL_BIN_DIR}/dbus-broker-launch --scope system#"
  )"
  backup_existing_path "$DBUS_BROKER_SYSTEM_UNIT_PATH"
  write_root_file "$DBUS_BROKER_SYSTEM_UNIT_PATH" 0644 "$unit_content"
}

render_user_bus_unit() {
  local source unit_content
  source="$DBUS_BROKER_STAGE_DIR/usr/lib/systemd/user/dbus-broker.service"
  unit_content="$(
    strip_install_section "$source" | sed "s#^ExecStart=.*#ExecStart=${DBUS_BROKER_INSTALL_BIN_DIR}/dbus-broker-launch --scope user#"
  )"
  backup_existing_path "$DBUS_BROKER_USER_UNIT_PATH"
  write_root_file "$DBUS_BROKER_USER_UNIT_PATH" 0644 "$unit_content"
}

render_managed_units() {
  [[ -n "${DBUS_BROKER_STAGE_DIR:-}" ]] || die "dbus-broker staged tree is not prepared"
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
  local fallback_fragment alias_path

  restore_backed_up_path "$DBUS_BROKER_SYSTEM_UNIT_PATH" || remove_if_present "$DBUS_BROKER_SYSTEM_UNIT_PATH"
  restore_backed_up_path "$DBUS_BROKER_USER_UNIT_PATH" || remove_if_present "$DBUS_BROKER_USER_UNIT_PATH"
  restore_backed_up_path "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker" || remove_unmanaged_artifact "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker"
  restore_backed_up_path "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker-launch" || remove_unmanaged_artifact "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker-launch"
  restore_backed_up_path "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker-session" || remove_unmanaged_artifact "$DBUS_BROKER_INSTALL_BIN_DIR/dbus-broker-session"
  restore_backed_up_path "$DBUS_BROKER_INSTALL_MAN_DIR/dbus-broker.1" || remove_unmanaged_artifact "$DBUS_BROKER_INSTALL_MAN_DIR/dbus-broker.1"
  restore_backed_up_path "$DBUS_BROKER_INSTALL_MAN_DIR/dbus-broker-launch.1" || remove_unmanaged_artifact "$DBUS_BROKER_INSTALL_MAN_DIR/dbus-broker-launch.1"
  restore_backed_up_path "$DBUS_BROKER_LEGACY_PROVENANCE_PATH" || remove_unmanaged_artifact "$DBUS_BROKER_LEGACY_PROVENANCE_PATH"
  restore_backed_up_path "$DBUS_BROKER_LEGACY_VERIFICATION_PATH" || remove_unmanaged_artifact "$DBUS_BROKER_LEGACY_VERIFICATION_PATH"
  restore_backed_up_path "$DBUS_BROKER_BUILD_PROVENANCE_PATH" || remove_unmanaged_artifact "$DBUS_BROKER_BUILD_PROVENANCE_PATH"
  restore_backed_up_path "$DBUS_BROKER_BUILD_VERIFICATION_PATH" || remove_unmanaged_artifact "$DBUS_BROKER_BUILD_VERIFICATION_PATH"
  restore_backed_up_path "$DBUS_BROKER_SUBPROJECTS_LOCK_INSTALL_PATH" || remove_unmanaged_artifact "$DBUS_BROKER_SUBPROJECTS_LOCK_INSTALL_PATH"
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

  cleanup_build_workspace
  remove_if_present "$DBUS_BROKER_CARGO_HOME"
  remove_if_present "$DBUS_BROKER_RUSTUP_HOME"
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
