#!/usr/bin/env bash

readonly MAINTENANCE_PACKAGES=(
  timeshift
  btrfsmaintenance
  btrfs-progs
  desktop-file-utils
  inotify-tools
  git
  grub-common
  grub2-common
  pkexec
)

retry_cmd() {
  local attempts="$1"
  shift
  local try=1
  while true; do
    if run_cmd "$@"; then
      return 0
    fi
    if (( try >= attempts )); then
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

debian_suite_value() {
  local suite="${DEBIAN_SUITE:-}"
  [[ -n "$suite" ]] || die "DEBIAN_SUITE must be set in ${ENV_FILE:-08-maintenance/.env}"
  [[ "$suite" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "DEBIAN_SUITE contains unsupported characters: '$suite'"
  printf '%s\n' "$suite"
}

apt_target_args() {
  local suite=""
  suite="$(debian_suite_value)"
  printf '%s\n' "-t" "$suite"
}

apt_update() {
  retry_cmd 3 env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt update -o Acquire::Retries=3 -o Acquire::http::Timeout=20
}

install_maintenance_packages() {
  local -a apt_args=()
  local -a target_args=()
  mapfile -t apt_args < <(apt_yes_args)
  mapfile -t target_args < <(apt_target_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none \
    apt install --no-install-recommends "${target_args[@]}" "${apt_args[@]}" "${MAINTENANCE_PACKAGES[@]}"
}
