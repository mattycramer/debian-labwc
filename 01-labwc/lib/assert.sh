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

require_backports_configured() {
  apt-cache policy | grep -F "trixie-backports" >/dev/null || die "trixie-backports is not configured"
}

require_file() {
  [[ -f "$1" ]] || die "missing file: $1"
}
