#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT
readonly BACKPORTS_SUITE="trixie-backports"
readonly BOOTSTRAP_PACKAGES=(
  bash
  make
  curl
  ca-certificates
  git
  grep
  sed
  gawk
  findutils
  coreutils
  util-linux
  procps
  pciutils
)

log() {
  printf '[runme] %s\n' "$*"
}

die() {
  printf '[runme] ERROR: %s\n' "$*" >&2
  exit 1
}

retry() {
  local attempts="$1"
  shift
  local n=1
  while true; do
    if "$@"; then
      return 0
    fi
    if (( n >= attempts )); then
      return 1
    fi
    sleep "$n"
    n=$((n + 1))
  done
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "run as root"
}

require_trixie() {
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
  apt-cache policy | grep -F "$BACKPORTS_SUITE" >/dev/null || die "$BACKPORTS_SUITE is not configured"
}

require_backports_candidates() {
  local pkg
  for pkg in "${BOOTSTRAP_PACKAGES[@]}"; do
    apt-cache policy "$pkg" | grep -F "$BACKPORTS_SUITE" >/dev/null || die "package '$pkg' has no $BACKPORTS_SUITE candidate"
  done
}

apt_update() {
  log "updating apt metadata"
  retry 3 env DEBIAN_FRONTEND=noninteractive apt update -o Acquire::Retries=3 -o Acquire::http::Timeout=20
}

install_bootstrap() {
  log "installing bootstrap packages from $BACKPORTS_SUITE"
  env DEBIAN_FRONTEND=noninteractive apt -t "$BACKPORTS_SUITE" install --no-install-recommends -y "${BOOTSTRAP_PACKAGES[@]}"
}

main() {
  require_root
  require_trixie
  require_amd64
  require_backports_configured
  apt_update
  require_backports_candidates
  install_bootstrap
  log "next: cd '$REPO_ROOT/01-labwc' && make install"
}

main "$@"
