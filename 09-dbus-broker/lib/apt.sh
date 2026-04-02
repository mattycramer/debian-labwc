#!/usr/bin/env bash

readonly SID_SUITE="sid"
readonly SID_SOURCE_PATH="/etc/apt/sources.list.d/sid.sources"
readonly SID_PREFERENCES_PATH="/etc/apt/preferences.d/sid"
readonly DEBIAN_ARCHIVE_KEYRING_PATH="/usr/share/keyrings/debian-archive-keyring.gpg"

readonly DBUS_RUNTIME_PACKAGES=(
  ca-certificates
  curl
  dbus
  dbus-daemon
  dbus-user-session
  libapparmor1
  libexpat1
  libsystemd0
  tar
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
    apt update -o Acquire::Retries=3 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 -o DPkg::Lock::Timeout=60
}

require_sid_repository() {
  [[ -f "$DEBIAN_ARCHIVE_KEYRING_PATH" ]] || die "missing Debian archive keyring: $DEBIAN_ARCHIVE_KEYRING_PATH"
  [[ -f "$SID_SOURCE_PATH" ]] || die "missing Debian sid source file: $SID_SOURCE_PATH; run 'make sid' in 00-system first"
  [[ -f "$SID_PREFERENCES_PATH" ]] || die "missing Debian sid preferences file: $SID_PREFERENCES_PATH; run 'make sid' in 00-system first"
}

install_dbus_runtime_packages() {
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  retry_cmd 3 env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none \
    apt -t "$SID_SUITE" install --no-install-recommends -o DPkg::Lock::Timeout=60 "${apt_args[@]}" "${DBUS_RUNTIME_PACKAGES[@]}"
}

package_is_installed() {
  dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null | grep -F "install ok installed" >/dev/null
}
