#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT
readonly BOOTSTRAP_PACKAGES=(
  bash
  make
  curl
  ca-certificates
  git
  grep
  sed
  gawk
  sudo
  findutils
  coreutils
  util-linux
  procps
  pciutils
)

detect_target_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]] && id "${SUDO_USER:-}" >/dev/null 2>&1; then
    TARGET_USER="$SUDO_USER"
  else
    TARGET_USER="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /(false|nologin)$/ {print $1; exit}')"
  fi
  [[ -n "${TARGET_USER:-}" ]] || die "could not determine target user"
  TARGET_HOME="$(getent passwd "$TARGET_USER" | awk -F: '{print $6}')"
  [[ -n "${TARGET_HOME:-}" ]] || die "could not determine target user home"
}

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

apt_update() {
  log "updating apt metadata"
  retry 3 env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt update -o Acquire::Retries=3 -o Acquire::http::Timeout=20
}

install_bootstrap() {
  log "installing bootstrap packages"
  env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt install --no-install-recommends -y "${BOOTSTRAP_PACKAGES[@]}"
}

repair_target_home() {
  log "repairing target home ownership and base directories"
  install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_USER" \
    "$TARGET_HOME" \
    "$TARGET_HOME/.config" \
    "$TARGET_HOME/.cache" \
    "$TARGET_HOME/.local" \
    "$TARGET_HOME/.local/bin" \
    "$TARGET_HOME/.local/share"
  chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME"
  chmod 0755 "$TARGET_HOME"
  chown -R "$TARGET_USER:$TARGET_USER" \
    "$TARGET_HOME/.config" \
    "$TARGET_HOME/.cache" \
    "$TARGET_HOME/.local"
}

main() {
  require_root
  require_trixie
  require_amd64
  detect_target_user
  apt_update
  install_bootstrap
  repair_target_home
  log "next:"
  log "  cd '$REPO_ROOT/01-labwc' && make install"
  log "  cd '$REPO_ROOT/04-dev' && make install"
  log "  cd '$REPO_ROOT/06-crystal-dock' && make install    # optional, Crystal Dock for Labwc"
  log "  cd '$REPO_ROOT/02-nvidia' && make install   # optional, NVIDIA hosts only"
  log "  cd '$REPO_ROOT/03-tools' && make install"
  log "  cd '$REPO_ROOT/05-security' && make install"
}

main "$@"
