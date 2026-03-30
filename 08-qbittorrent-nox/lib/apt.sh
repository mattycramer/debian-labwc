#!/usr/bin/env bash

readonly SID_SUITE="sid"
readonly QBT_PACKAGES=(
  apparmor
  apparmor-utils
)
readonly QBT_SID_PACKAGES=(
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

apt_update() {
  retry_cmd 3 env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none \
    apt update -o Acquire::Retries=3 -o Acquire::http::Timeout=20
}

install_qbittorrent_packages() {
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none \
    apt install --no-install-recommends "${apt_args[@]}" "${QBT_PACKAGES[@]}"
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none \
    apt -t "$SID_SUITE" install --no-install-recommends "${apt_args[@]}" "${QBT_SID_PACKAGES[@]}"
}

package_is_installed() {
  dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null | grep -F "install ok installed" >/dev/null
}
