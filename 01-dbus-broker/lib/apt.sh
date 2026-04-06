#!/usr/bin/env bash

readonly DBUS_RUNTIME_PACKAGES=(
  ca-certificates
  curl
  jq
  dbus
  dbus-daemon
  dbus-user-session
  gzip
  libapparmor1
  libexpat1
  libsystemd0
  tar
)

readonly DBUS_SOURCE_BUILD_PACKAGES=(
  git
  bindgen
  build-essential
  clang
  libapparmor-dev
  libclang-dev
  libexpat1-dev
  libsystemd-dev
  lld
  meson
  ninja-build
  pkgconf
  python3-docutils
  rustup
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

debian_suite_value() {
  local suite="${DEBIAN_SUITE:-}"
  [[ -n "$suite" ]] || die "DEBIAN_SUITE must be set in ${ENV_FILE:-01-dbus-broker/.env}"
  [[ "$suite" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "DEBIAN_SUITE contains unsupported characters: '$suite'"
  printf '%s\n' "$suite"
}

apt_target_args() {
  local suite=""
  suite="$(debian_suite_value)"
  printf '%s\n' "-t" "$suite"
}

apt_update() {
  retry_cmd 3 env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none \
    apt update -o Acquire::Retries=3 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 -o DPkg::Lock::Timeout=60
}

install_dbus_runtime_packages() {
  local -a apt_args=()
  local -a target_args=()
  mapfile -t apt_args < <(apt_yes_args)
  mapfile -t target_args < <(apt_target_args)
  retry_cmd 3 env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none \
    apt install --no-install-recommends -o DPkg::Lock::Timeout=60 "${target_args[@]}" "${apt_args[@]}" "${DBUS_RUNTIME_PACKAGES[@]}"
  if [[ "${DBUS_BROKER_INSTALL_METHOD:-source}" == "source" ]]; then
    retry_cmd 3 env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none \
      apt install --no-install-recommends -o DPkg::Lock::Timeout=60 "${target_args[@]}" "${apt_args[@]}" "${DBUS_SOURCE_BUILD_PACKAGES[@]}"
  fi
}

package_is_installed() {
  dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null | grep -F "install ok installed" >/dev/null
}
