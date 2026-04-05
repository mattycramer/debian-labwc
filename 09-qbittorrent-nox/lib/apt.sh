#!/usr/bin/env bash

readonly QBT_PACKAGES=(
  apparmor
  apparmor-utils
)
readonly QBT_RUNTIME_PACKAGES=(
  qbittorrent-nox
)

retry_cmd() {
  local attempts="$1"
  shift
  local try=1
  while true; do
    if run_cmd "$@"; then
      return 0
    fi
    if ((try >= attempts)); then
      return 1
    fi
    sleep "$try"
    try=$((try + 1))
  done
}

apt_yes_args() {
  if [[ "${ASSUME_YES:-1}" -eq 1 ]]; then
    printf '%s\n' "-y"
  fi
}

apt_target_args() {
  local suite="${QBT_APT_TARGET_SUITE:-}"
  [[ -z "$suite" ]] && return 0
  [[ "$suite" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "QBT_APT_TARGET_SUITE contains unsupported characters: '$suite'"
  printf '%s\n' "-t" "$suite"
}

apt_update() {
  retry_cmd 3 env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none \
    apt update -o Acquire::Retries=3 -o Acquire::http::Timeout=20 -o DPkg::Lock::Timeout=60
}

install_qbittorrent_packages() {
  local -a apt_args=()
  local -a target_args=()
  mapfile -t apt_args < <(apt_yes_args)
  mapfile -t target_args < <(apt_target_args)
  retry_cmd 3 env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none \
    apt install --no-install-recommends -o DPkg::Lock::Timeout=60 "${target_args[@]}" "${apt_args[@]}" "${QBT_PACKAGES[@]}"
  retry_cmd 3 env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none \
    apt install --no-install-recommends -o DPkg::Lock::Timeout=60 "${target_args[@]}" "${apt_args[@]}" "${QBT_RUNTIME_PACKAGES[@]}"
}

package_is_installed() {
  dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null | grep -F "install ok installed" >/dev/null
}
