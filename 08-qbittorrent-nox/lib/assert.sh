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

require_exact_mountpoint() {
  local path="$1"
  local target
  target="$(findmnt -rn -M "$path" -o TARGET 2>/dev/null || true)"
  [[ "$target" == "$path" ]] || die "required mountpoint is not mounted exactly at '$path'"
}

require_port_number() {
  local label="$1"
  local value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || die "$label must be a numeric TCP/UDP port, found '$value'"
  ((value >= 1 && value <= 65535)) || die "$label must be between 1 and 65535, found '$value'"
}

require_positive_integer() {
  local label="$1"
  local value="$2"
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || die "$label must be a positive integer, found '$value'"
}

require_nonnegative_integer() {
  local label="$1"
  local value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || die "$label must be a non-negative integer, found '$value'"
}

require_integer_or_minus_one() {
  local label="$1"
  local value="$2"
  [[ "$value" =~ ^-1$|^[0-9]+$ ]] || die "$label must be -1 or a non-negative integer, found '$value'"
}

require_decimal_number() {
  local label="$1"
  local value="$2"
  [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "$label must be a decimal number, found '$value'"
}

require_safe_token() {
  local label="$1"
  local value="$2"
  [[ "$value" =~ ^[A-Za-z0-9._:-]+$ ]] || die "$label contains unsupported characters: '$value'"
}
