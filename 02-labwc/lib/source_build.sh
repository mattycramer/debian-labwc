#!/usr/bin/env bash

readonly LABWC_SOURCE_BUILD_STATE_DIR="/var/lib/labwc-session"
readonly LABWC_BUILD_LOG_DIR="/var/log/labwc-build"
readonly LABWC_PERSISTENT_BUILD_ROOT="/pool/builds/labwc"

prepare_build_log_dir() {
  run_cmd install -d -m 0755 "$LABWC_BUILD_LOG_DIR"
}

ensure_persistent_build_root() {
  run_cmd install -d -m 0755 /pool /pool/builds "$LABWC_PERSISTENT_BUILD_ROOT"
}

persistent_component_work_root() {
  local component_name="$1"
  require_safe_token "persistent build component" "$component_name"
  printf '%s/%s\n' "$LABWC_PERSISTENT_BUILD_ROOT" "$component_name"
}

prepare_persistent_component_work_root() {
  local component_name="$1"
  local work_root=""

  ensure_persistent_build_root
  work_root="$(persistent_component_work_root "$component_name")"
  if [[ -n "${LABWC_TARGET_USER:-}" && "${LABWC_TARGET_USER}" != "root" ]]; then
    run_cmd install -d -m 0755 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_GROUP" "$work_root"
    run_cmd chown -R "$LABWC_TARGET_USER:$LABWC_TARGET_GROUP" "$work_root"
  else
    run_cmd install -d -m 0755 "$work_root"
  fi
  printf '%s\n' "$work_root"
}

run_git_in_checkout() {
  local repo_dir="$1"
  shift

  if declare -F run_target_user_command >/dev/null 2>&1 \
    && [[ -n "${LABWC_TARGET_USER:-}" ]] \
    && [[ "${LABWC_TARGET_USER}" != "root" ]]; then
    run_target_user_command -- git -C "$repo_dir" "$@"
    return 0
  fi

  run_cmd git -C "$repo_dir" "$@"
}

build_log_path() {
  local name="$1"
  printf '%s/%s.log\n' "$LABWC_BUILD_LOG_DIR" "$name"
}

run_logged_command() {
  local log_path="$1"
  shift
  local rc=0

  prepare_build_log_dir
  {
    printf '[%s] CMD:' "$(timestamp)"
    printf ' %q' "$@"
    printf '\n'
  } >>"$log_path"

  if command -v tee >/dev/null 2>&1; then
    set +e
    "$@" 2>&1 | tee -a "$log_path" >&2
    rc=${PIPESTATUS[0]}
    set -e
  else
    set +e
    "$@" >>"$log_path" 2>&1
    rc=$?
    set -e
  fi

  if ((rc != 0)); then
    printf '[%s] ERROR: command failed with exit status %s\n' "$(timestamp)" "$rc" >>"$log_path"
  fi
  return "$rc"
}

remove_manifest_install() {
  local manifest_path="$1"
  local line path
  local -a dir_paths=()

  [[ -f "$manifest_path" ]] || return 0

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    case "$line" in
      d:*)
        dir_paths+=("${line#d:}")
        ;;
      f:*)
        remove_if_present "${line#f:}"
        ;;
      /*)
        remove_if_present "$line"
        ;;
      *)
        log_warn "ignoring unexpected manifest entry in $manifest_path: $line"
        ;;
    esac
  done <"$manifest_path"

  if ((${#dir_paths[@]} > 0)); then
    while IFS= read -r path; do
      [[ -n "$path" ]] || continue
      rmdir "$path" >/dev/null 2>&1 || true
    done < <(printf '%s\n' "${dir_paths[@]}" | LC_ALL=C sort -r)
  fi

  remove_if_present "$manifest_path"
}

install_staged_tree() {
  local source_root="$1"
  local manifest_path="$2"
  local manifest_tmp
  local source_path relative_path destination_path mode

  require_dir "$source_root"
  manifest_tmp="$(mktemp)"

  if ! find "$source_root" -type f -print -quit | grep -q .; then
    rm -f -- "$manifest_tmp"
    die "staged install tree under $source_root does not contain any files"
  fi

  : >"$manifest_tmp"

  while IFS= read -r source_path; do
    relative_path="${source_path#"$source_root"/}"
    [[ -n "$relative_path" ]] || continue
    destination_path="/$relative_path"
    mode="$(stat -c '%a' "$source_path")"
    if [[ ! -d "$destination_path" ]]; then
      run_cmd install -d -m "$mode" "$destination_path"
      printf 'd:%s\n' "$destination_path" >>"$manifest_tmp"
    fi
  done < <(find "$source_root" -mindepth 1 -type d | LC_ALL=C sort)

  while IFS= read -r source_path; do
    relative_path="${source_path#"$source_root"/}"
    [[ -n "$relative_path" ]] || continue
    destination_path="/$relative_path"
    mode="$(stat -c '%a' "$source_path")"
    run_cmd install -D -m "$mode" "$source_path" "$destination_path"
    printf 'f:%s\n' "$destination_path" >>"$manifest_tmp"
  done < <(find "$source_root" -type f | LC_ALL=C sort)

  run_cmd install -d -m 0755 "$(dirname "$manifest_path")"
  run_cmd install -m 0644 "$manifest_tmp" "$manifest_path"
  rm -f -- "$manifest_tmp"
}

normalize_git_url() {
  local url="$1"
  url="${url%/}"
  url="${url%.git}"
  printf '%s\n' "$url"
}

normalize_sha256_value() {
  local value="$1"
  value="${value#sha256:}"
  printf '%s\n' "${value,,}"
}

verify_file_sha256() {
  local file_path="$1"
  local expected_sha actual_sha

  expected_sha="$(normalize_sha256_value "$2")"
  require_sha256_hex "$expected_sha"
  require_file "$file_path"
  actual_sha="$(sha256sum "$file_path" | awk '{print $1}')"
  [[ "$actual_sha" == "$expected_sha" ]] || {
    die "sha256 mismatch for '$file_path': expected '$expected_sha', got '$actual_sha'"
  }
}

validate_tarball_members_safe() {
  local tarball_path="$1"

  require_file "$tarball_path"
  python3 - "$tarball_path" <<'PY'
from pathlib import PurePosixPath
import sys
import tarfile

tarball_path = sys.argv[1]

with tarfile.open(tarball_path, "r:gz") as archive:
    for member in archive.getmembers():
        path = PurePosixPath(member.name)
        if path.is_absolute():
            raise SystemExit(f"tarball entry must not be absolute: {member.name}")
        if any(part == ".." for part in path.parts):
            raise SystemExit(f"tarball entry must not contain parent traversal: {member.name}")
        if member.issym() or member.islnk():
            raise SystemExit(f"tarball entry must not be a symlink or hard link: {member.name}")
        if member.isdev():
            raise SystemExit(f"tarball entry must not be a device node: {member.name}")
PY
}

download_release_tarball() {
  local artifact_name="$1"
  local tarball_url="$2"
  local tarball_sha="$3"
  local log_path="${4:-}"
  local work_root tarball_path

  require_https_url "${artifact_name} tarball url" "$tarball_url"
  require_sha256_hex "$(normalize_sha256_value "$tarball_sha")"

  work_root="$(mktemp -d "/tmp/${artifact_name}.XXXXXX")"
  tarball_path="$work_root/archive.tar.gz"

  if [[ -n "$log_path" ]]; then
    retry_cmd 3 run_logged_command "$log_path" curl --fail --location --max-time 60 --silent --show-error -o "$tarball_path" "$tarball_url"
  else
    retry_cmd 3 curl --fail --location --max-time 60 --silent --show-error -o "$tarball_path" "$tarball_url"
  fi

  verify_file_sha256 "$tarball_path" "$tarball_sha"
  validate_tarball_members_safe "$tarball_path"
  printf '%s\n' "$work_root"
}

extract_release_tarball() {
  local tarball_path="$1"
  local destination_dir="$2"

  require_file "$tarball_path"
  run_cmd install -d -m 0755 "$destination_dir"
  validate_tarball_members_safe "$tarball_path"
  run_cmd tar -xzf "$tarball_path" -C "$destination_dir"
}

verify_checkout_remote() {
  local repo_dir="$1"
  local expected_url="$2"
  local actual_url

  actual_url="$(run_git_in_checkout "$repo_dir" remote get-url origin)"
  [[ "$(normalize_git_url "$actual_url")" == "$(normalize_git_url "$expected_url")" ]] || {
    die "unexpected git remote for $repo_dir: expected '$expected_url', got '$actual_url'"
  }
}

apply_patch_series_if_present() {
  local repo_dir="$1"
  local series_path="$repo_dir/patches/release/series"
  local patch_path=""
  local series_entry=""

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

    if run_git_in_checkout "$repo_dir" apply --check "$patch_path" >/dev/null 2>&1; then
      run_git_in_checkout "$repo_dir" apply "$patch_path"
      continue
    fi

    run_git_in_checkout "$repo_dir" apply --reverse --check "$patch_path" >/dev/null 2>&1 || {
      die "release patch '$series_entry' is neither applicable nor already applied in $repo_dir"
    }
  done <"$series_path"
}

fetch_source_checkout() {
  local repo_name="$1"
  local source_url="$2"
  local commit_sha="$3"
  local log_path="${4:-}"
  local work_root repo_dir current_url

  require_https_url "${repo_name} source url" "$source_url"
  require_commit_sha "$commit_sha"

  work_root="$(prepare_persistent_component_work_root "$repo_name")"
  repo_dir="$work_root/source"

  if [[ -e "$repo_dir" && ! -d "$repo_dir/.git" ]]; then
    run_cmd rm -rf -- "$repo_dir" "$work_root/build" "$work_root/stage" "$work_root/target" "$work_root/prefix"
  fi

  if [[ -d "$repo_dir/.git" ]]; then
    current_url="$(run_git_in_checkout "$repo_dir" remote get-url origin 2>/dev/null || true)"
    if [[ -z "$current_url" || "$(normalize_git_url "$current_url")" != "$(normalize_git_url "$source_url")" ]]; then
      run_cmd rm -rf -- "$repo_dir" "$work_root/build" "$work_root/stage" "$work_root/target" "$work_root/prefix"
    fi
  fi

  if [[ ! -d "$repo_dir/.git" ]]; then
    if declare -F run_target_user_command >/dev/null 2>&1 \
      && [[ -n "${LABWC_TARGET_USER:-}" ]] \
      && [[ "${LABWC_TARGET_USER}" != "root" ]]; then
      retry_cmd 3 run_target_user_command -- git clone --quiet --filter=blob:none "$source_url" "$repo_dir"
    elif [[ -n "$log_path" ]]; then
      retry_cmd 3 run_logged_command "$log_path" git clone --quiet --filter=blob:none "$source_url" "$repo_dir"
    else
      retry_cmd 3 git clone --quiet --filter=blob:none "$source_url" "$repo_dir"
    fi
  fi

  if declare -F run_target_user_command >/dev/null 2>&1 \
    && [[ -n "${LABWC_TARGET_USER:-}" ]] \
    && [[ "${LABWC_TARGET_USER}" != "root" ]]; then
    retry_cmd 3 run_target_user_command -- git -C "$repo_dir" fetch --quiet --depth 1 origin "$commit_sha"
    run_target_user_command -- git -C "$repo_dir" checkout --quiet --detach "$commit_sha"
  else
    if [[ -n "$log_path" ]]; then
      retry_cmd 3 run_logged_command "$log_path" git -C "$repo_dir" fetch --quiet --depth 1 origin "$commit_sha"
      run_logged_command "$log_path" git -C "$repo_dir" checkout --quiet --detach "$commit_sha"
    else
      retry_cmd 3 git -C "$repo_dir" fetch --quiet --depth 1 origin "$commit_sha"
      run_cmd git -C "$repo_dir" checkout --quiet --detach "$commit_sha"
    fi
  fi
  verify_checkout_remote "$repo_dir" "$source_url"
  [[ "$(run_git_in_checkout "$repo_dir" rev-parse HEAD)" == "$commit_sha" ]] || {
    die "${repo_name} checkout did not resolve to expected commit '$commit_sha'"
  }

  apply_patch_series_if_present "$repo_dir"

  printf '%s\n' "$work_root"
}

cleanup_source_checkout() {
  local work_root="$1"
  [[ -n "$work_root" ]] || return 0
  if [[ "$work_root" == "$LABWC_PERSISTENT_BUILD_ROOT/"* ]]; then
    return 0
  fi
  [[ "$work_root" == /tmp/* ]] || die "refusing to remove unexpected source checkout path: $work_root"
  run_cmd rm -rf -- "$work_root"
}

ensure_source_state_dir() {
  run_cmd install -d -m 0755 "$LABWC_SOURCE_BUILD_STATE_DIR"
}

remove_persistent_build_workspace() {
  local component_name="$1"
  local work_root=""

  work_root="$(persistent_component_work_root "$component_name")"
  [[ "$work_root" == "$LABWC_PERSISTENT_BUILD_ROOT/"* ]] || die "refusing to remove unexpected persistent build root: $work_root"
  if [[ -e "$work_root" ]]; then
    run_cmd rm -rf -- "$work_root"
  fi
}

native_cflags() {
  printf '%s\n' "-O3 -march=native -mtune=native -pipe -fno-plt"
}

native_cxxflags() {
  printf '%s\n' "$(native_cflags)"
}

native_ldflags() {
  printf '%s\n' "-Wl,-O2 -Wl,--as-needed -fuse-ld=lld"
}

native_rustflags() {
  printf '%s\n' "-C target-cpu=native -C opt-level=3 -C codegen-units=1 -C strip=symbols"
}

rust_toolchain_bin_dir() {
  printf '%s/toolchain-bin\n' "$1"
}

ensure_rustup_toolchain() {
  local state_root="$1"
  local toolchain="$2"
  local toolchain_bin_dir cargo_bin rustc_bin
  local log_path="${3:-}"

  [[ "$state_root" == /var/lib/* ]] || die "rust state root must stay under /var/lib: $state_root"
  [[ "$toolchain" =~ ^nightly-[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || {
    die "rust toolchain must be a dated nightly, found '$toolchain'"
  }

  require_command rustup
  if [[ -n "$log_path" ]]; then
    run_logged_command "$log_path" rustup toolchain install "$toolchain" --profile minimal
  else
    run_cmd rustup toolchain install "$toolchain" --profile minimal
  fi

  cargo_bin="$(rustup which cargo --toolchain "$toolchain")"
  rustc_bin="$(rustup which rustc --toolchain "$toolchain")"
  require_file "$cargo_bin"
  require_file "$rustc_bin"

  toolchain_bin_dir="$(rust_toolchain_bin_dir "$state_root")"
  run_cmd install -d -m 0755 "$state_root" "$toolchain_bin_dir"
  run_cmd ln -sfn "$cargo_bin" "$toolchain_bin_dir/cargo"
  run_cmd ln -sfn "$rustc_bin" "$toolchain_bin_dir/rustc"
}

run_with_rust_toolchain() {
  local state_root="$1"
  local toolchain="$2"
  shift 2

  env \
    PATH="$(rust_toolchain_bin_dir "$state_root"):$PATH" \
    "$@"
}

rust_version_output() {
  local state_root="$1"
  local toolchain="$2"
  run_with_rust_toolchain "$state_root" "$toolchain" rustc --version
}

cargo_version_output() {
  local state_root="$1"
  local toolchain="$2"
  run_with_rust_toolchain "$state_root" "$toolchain" cargo --version
}

write_source_provenance() {
  local destination="$1"
  local content="$2"

  run_cmd install -d -m 0755 "$(dirname "$destination")"
  printf '%s' "$content" >"$destination"
  run_cmd chmod 0644 "$destination"
}

assert_binary_dependencies() {
  local binary_path="$1"
  local binary_name="$2"
  local missing_output

  [[ -x "$binary_path" ]] || die "$binary_name binary is missing or not executable: $binary_path"
  missing_output="$(ldd "$binary_path" 2>&1 | awk '/not found/ {print}')"
  [[ -z "$missing_output" ]] || {
    die "$binary_name binary has unresolved shared-library dependencies:
$missing_output"
  }
}
