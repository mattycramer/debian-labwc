#!/usr/bin/env bash

readonly LABWC_SOURCE_BUILD_STATE_DIR="/var/lib/labwc-session"

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
    run_cmd install -d -m "$mode" "$destination_path"
    printf 'd:%s\n' "$destination_path" >>"$manifest_tmp"
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

    if git -C "$repo_dir" apply --check "$patch_path" >/dev/null 2>&1; then
      run_cmd git -C "$repo_dir" apply "$patch_path"
      continue
    fi

    git -C "$repo_dir" apply --reverse --check "$patch_path" >/dev/null 2>&1 || {
      die "release patch '$series_entry' is neither applicable nor already applied in $repo_dir"
    }
  done <"$series_path"
}

fetch_source_checkout() {
  local repo_name="$1"
  local source_url="$2"
  local commit_sha="$3"
  local work_root repo_dir

  require_https_url "${repo_name} source url" "$source_url"
  require_commit_sha "$commit_sha"

  work_root="$(mktemp -d "/tmp/${repo_name}.XXXXXX")"
  repo_dir="$work_root/source"

  retry_cmd 3 git clone --quiet --filter=blob:none "$source_url" "$repo_dir"
  retry_cmd 3 git -C "$repo_dir" fetch --quiet --depth 1 origin "$commit_sha"
  run_cmd git -C "$repo_dir" checkout --quiet --detach "$commit_sha"
  verify_checkout_remote "$repo_dir" "$source_url"
  [[ "$(git -C "$repo_dir" rev-parse HEAD)" == "$commit_sha" ]] || {
    die "${repo_name} checkout did not resolve to expected commit '$commit_sha'"
  }

  apply_patch_series_if_present "$repo_dir"

  printf '%s\n' "$work_root"
}

cleanup_source_checkout() {
  local work_root="$1"
  [[ -n "$work_root" ]] || return 0
  [[ "$work_root" == /tmp/* ]] || die "refusing to remove unexpected source checkout path: $work_root"
  run_cmd rm -rf -- "$work_root"
}

ensure_source_state_dir() {
  run_cmd install -d -m 0755 "$LABWC_SOURCE_BUILD_STATE_DIR"
}

rust_home_dir() {
  printf '%s/cargo\n' "$1"
}

rustup_home_dir() {
  printf '%s/rustup\n' "$1"
}

ensure_rustup_toolchain() {
  local state_root="$1"
  local toolchain="$2"
  local cargo_home rustup_home rustup_bin init_script

  [[ "$state_root" == /var/lib/* ]] || die "rust state root must stay under /var/lib: $state_root"
  [[ "$toolchain" =~ ^nightly-[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || {
    die "rust toolchain must be a dated nightly, found '$toolchain'"
  }

  cargo_home="$(rust_home_dir "$state_root")"
  rustup_home="$(rustup_home_dir "$state_root")"
  rustup_bin="$cargo_home/bin/rustup"

  run_cmd install -d -m 0755 "$state_root"
  run_cmd install -d -m 0755 "$cargo_home" "$rustup_home"

  if [[ ! -x "$rustup_bin" ]]; then
    init_script="$(mktemp "/tmp/rustup-init.XXXXXX.sh")"
    retry_cmd 3 curl --fail --location --max-time 180 --silent --show-error \
      -o "$init_script" "https://sh.rustup.rs"
    run_cmd chmod 0755 "$init_script"
    run_cmd env CARGO_HOME="$cargo_home" RUSTUP_HOME="$rustup_home" sh "$init_script" -y --profile minimal --default-toolchain none
    run_cmd rm -f -- "$init_script"
  fi

  run_cmd env CARGO_HOME="$cargo_home" RUSTUP_HOME="$rustup_home" "$rustup_bin" toolchain install "$toolchain" --profile minimal
}

run_with_rust_toolchain() {
  local state_root="$1"
  local toolchain="$2"
  shift 2

  env \
    CARGO_HOME="$(rust_home_dir "$state_root")" \
    RUSTUP_HOME="$(rustup_home_dir "$state_root")" \
    PATH="$(rust_home_dir "$state_root")/bin:$PATH" \
    "$@"
}

rust_version_output() {
  local state_root="$1"
  local toolchain="$2"
  run_with_rust_toolchain "$state_root" "$toolchain" rustc +"$toolchain" --version
}

cargo_version_output() {
  local state_root="$1"
  local toolchain="$2"
  run_with_rust_toolchain "$state_root" "$toolchain" cargo +"$toolchain" --version
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
