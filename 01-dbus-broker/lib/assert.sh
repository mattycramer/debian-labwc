#!/usr/bin/env bash

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "run as root"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

require_debian_trixie() {
  local codename
  codename="$(
    # shellcheck disable=SC1091
    . /etc/os-release
    printf '%s' "${VERSION_CODENAME:-}"
  )"
  [[ "$codename" == "trixie" ]] || die "expected Debian trixie, found '${codename:-unknown}'"
}

require_amd64() {
  local arch
  arch="$(dpkg --print-architecture)"
  [[ "$arch" == "amd64" ]] || die "expected amd64, found '$arch'"
}

require_file() {
  [[ -f "$1" ]] || die "missing file: $1"
}

require_directory() {
  [[ -d "$1" ]] || die "missing directory: $1"
}

require_sha256_hex() {
  local value="$1"
  [[ "$value" =~ ^[0-9a-f]{64}$ ]] || die "invalid sha256 value: '$value'"
}

require_commit_sha() {
  local value="$1"
  [[ "$value" =~ ^[0-9a-f]{40}$ ]] || die "invalid commit sha: '$value'"
}

require_yes_no() {
  local label="$1"
  local value="$2"
  [[ "$value" == "yes" || "$value" == "no" ]] || die "$label must be 'yes' or 'no', found '$value'"
}

require_https_url() {
  local label="$1"
  local value="$2"
  [[ "$value" == https://* ]] || die "$label must be an https URL, found '$value'"
  [[ "$value" != *" "* ]] || die "$label must not contain spaces, found '$value'"
}

require_safe_token() {
  local label="$1"
  local value="$2"
  [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]] || die "$label contains unsupported characters: '$value'"
}

require_absolute_path() {
  local label="$1"
  local value="$2"
  [[ "$value" == /* ]] || die "$label must be an absolute path, found '$value'"
  [[ "$value" != */..* ]] || die "$label must not contain traversal segments, found '$value'"
}

require_path_prefix() {
  local label="$1"
  local value="$2"
  local prefix="$3"
  [[ "$value" == "$prefix" || "$value" == "$prefix/"* ]] || die "$label must stay under '$prefix', found '$value'"
}
