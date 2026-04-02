#!/usr/bin/env bash

remove_release_manifest_install() {
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
        # Legacy manifests recorded plain file paths only.
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

normalize_release_archive_entry() {
  local entry="$1"

  while [[ "$entry" == ./* ]]; do
    entry="${entry#./}"
  done
  while [[ "$entry" == */ ]]; do
    entry="${entry%/}"
  done

  printf '%s\n' "$entry"
}

release_archive_entry_is_safe() {
  local entry="$1"
  local segment
  local IFS='/'
  local -a segments=()

  [[ -n "$entry" ]] || return 0
  [[ "$entry" != /* ]] || return 1

  read -r -a segments <<<"$entry"
  ((${#segments[@]} > 0)) || return 1

  for segment in "${segments[@]}"; do
    [[ -n "$segment" ]] || return 1
    [[ "$segment" != "." ]] || return 1
    [[ "$segment" != ".." ]] || return 1
  done

  return 0
}

validate_release_archive_tree() {
  local release_name="$1"
  local tarball_path="$2"
  local expected_prefix="$3"
  local entry normalized
  local -a tar_entries=()

  require_file "$tarball_path"
  [[ -n "$expected_prefix" ]] || die "$release_name expected prefix is empty"
  [[ "$expected_prefix" != /* ]] || die "$release_name expected prefix must be relative: $expected_prefix"

  mapfile -t tar_entries < <(tar -tf "$tarball_path")
  ((${#tar_entries[@]} > 0)) || die "$release_name tarball is empty"

  for entry in "${tar_entries[@]}"; do
    normalized="$(normalize_release_archive_entry "$entry")"
    [[ -n "$normalized" ]] || continue
    release_archive_entry_is_safe "$normalized" || {
      die "$release_name tarball contains an unsafe path entry: $entry"
    }
    [[ "$normalized" == "$expected_prefix" || "$normalized" == "$expected_prefix/"* || "$expected_prefix" == "$normalized/"* ]] || {
      die "$release_name tarball entry '$normalized' escapes expected prefix '$expected_prefix'"
    }
  done
}

download_release_tarball() {
  local release_name="$1"
  local release_url="$2"
  local expected_sha="$3"
  local tarball_path="$4"
  local actual_sha

  [[ "$release_url" == https://* ]] || die "$release_name release URL must use https: $release_url"
  [[ "$expected_sha" =~ ^[0-9a-f]{64}$ ]] || {
    die "$release_name tarball sha256 must be a 64 character lowercase hex digest, found '$expected_sha'"
  }

  retry_cmd 3 curl --ipv4 --fail --location --connect-timeout 20 --max-time 300 --silent --show-error -o "$tarball_path" "$release_url"
  actual_sha="$(sha256sum "$tarball_path" | awk '{print $1}')"
  [[ "$actual_sha" == "$expected_sha" ]] || {
    die "$release_name tarball sha256 mismatch: expected $expected_sha, got $actual_sha"
  }
}

extract_release_payload_tree() {
  local release_name="$1"
  local tarball_path="$2"
  local expected_prefix="$3"
  local extract_root="$4"
  local unexpected_path

  validate_release_archive_tree "$release_name" "$tarball_path" "$expected_prefix"
  run_cmd install -d -m 0755 "$extract_root"
  run_cmd tar -xf "$tarball_path" -C "$extract_root"

  unexpected_path="$(
    find "$extract_root" -mindepth 1 \( -type l -o -type b -o -type c -o -type p -o -type s \) -print -quit
  )"
  [[ -z "$unexpected_path" ]] || {
    die "$release_name tarball extracted an unsupported filesystem entry: ${unexpected_path#"$extract_root"/}"
  }

  require_dir "$extract_root/$expected_prefix"
}

install_release_payload_tree() {
  local extract_root="$1"
  local manifest_path="$2"
  local manifest_tmp
  local source_path relative_path destination_path mode

  require_dir "$extract_root"
  manifest_tmp="$(mktemp)"

  if ! find "$extract_root" -type f -print -quit | grep -q .; then
    rm -f -- "$manifest_tmp"
    die "release payload tree under $extract_root does not contain any files"
  fi

  : >"$manifest_tmp"

  while IFS= read -r source_path; do
    relative_path="${source_path#"$extract_root"/}"
    [[ -n "$relative_path" ]] || continue
    destination_path="/$relative_path"
    mode="$(stat -c '%a' "$source_path")"
    run_cmd install -d -m "$mode" "$destination_path"
    printf 'd:%s\n' "$destination_path" >>"$manifest_tmp"
  done < <(find "$extract_root" -mindepth 1 -type d | LC_ALL=C sort)

  while IFS= read -r source_path; do
    relative_path="${source_path#"$extract_root"/}"
    [[ -n "$relative_path" ]] || continue
    destination_path="/$relative_path"
    mode="$(stat -c '%a' "$source_path")"
    run_cmd install -D -m "$mode" "$source_path" "$destination_path"
    printf 'f:%s\n' "$destination_path" >>"$manifest_tmp"
  done < <(find "$extract_root" -type f | LC_ALL=C sort)

  run_cmd install -d -m 0755 "$(dirname "$manifest_path")"
  run_cmd install -m 0644 "$manifest_tmp" "$manifest_path"
  rm -f -- "$manifest_tmp"
}

assert_release_binary_dependencies() {
  local binary_path="$1"
  local release_name="$2"
  local missing_output

  [[ -x "$binary_path" ]] || die "$release_name binary is missing or not executable: $binary_path"
  missing_output="$(ldd "$binary_path" 2>&1 | awk '/not found/ {print}')"
  [[ -z "$missing_output" ]] || {
    die "$release_name binary has unresolved shared-library dependencies:
$missing_output"
  }
}
