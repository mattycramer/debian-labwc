#!/usr/bin/env bash

readonly SID_SUITE="sid"
readonly NVIDIA_PACKAGES=(
  build-essential
  "linux-headers-$(uname -r)"
  linux-headers-amd64
  nvidia-driver
  nvidia-kernel-dkms
  nvidia-vaapi-driver
  nvidia-vulkan-icd
)

apt_yes_args() {
  if [[ "${ASSUME_YES:-1}" -eq 1 ]]; then
    printf '%s\n' "-y"
  fi
}

apt_update() {
  log_info "updating apt metadata"
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt update -o Acquire::Retries=3 -o Acquire::http::Timeout=20
}

sid_archive_available() {
  apt-cache policy 2>/dev/null | grep -F ' n=sid' >/dev/null
}

install_nvidia_packages() {
  [[ "${NVIDIA_INSTALL:-1}" == "1" ]] || die "set NVIDIA_INSTALL=1 to install NVIDIA packages"
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  log_info "installing NVIDIA packages"
  sid_archive_available || die "sid archive is not configured on the system"
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt -t "$SID_SUITE" install --no-install-recommends "${apt_args[@]}" "${NVIDIA_PACKAGES[@]}"
}

verify_nvidia_install() {
  local pkg
  for pkg in "${NVIDIA_PACKAGES[@]}"; do
    dpkg-query -W -f='${Status}\n' "$pkg" 2>/dev/null | grep -F "install ok installed" >/dev/null || die "package '$pkg' is not installed"
  done
  [[ -e "/lib/modules/$(uname -r)/build" ]] || die "missing kernel build directory for $(uname -r)"
  command -v gcc >/dev/null 2>&1 || die "gcc is not installed"
}

remove_nvidia_packages() {
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  log_info "removing NVIDIA packages"
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt remove "${apt_args[@]}" "${NVIDIA_PACKAGES[@]}" || true
}
