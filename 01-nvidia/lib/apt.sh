#!/usr/bin/env bash

apt_yes_args() {
  if [[ "${ASSUME_YES:-1}" -eq 1 ]]; then
    printf '%s\n' "-y"
  fi
}

retry_mutating_cmd() {
  local attempts="$1"
  shift
  local try=1
  while true; do
    if run_mutating_cmd "$@"; then
      return 0
    fi
    if (( try >= attempts )); then
      return 1
    fi
    sleep "$try"
    try=$((try + 1))
  done
}

apt_update() {
  log_info "updating apt metadata"
  retry_mutating_cmd 3 env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt-get update -o Acquire::Retries=3 -o Acquire::http::Timeout=20
}

package_installed() {
  dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null | grep -Fx 'install ok installed' >/dev/null
}

install_package_group() {
  local label="$1"
  shift
  local -a apt_args=()
  local -a packages=( "$@" )
  if ((${#packages[@]} == 0)); then
    return 0
  fi
  mapfile -t apt_args < <(apt_yes_args)
  log_info "installing ${label}"
  run_mutating_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt-get install -V --no-install-recommends "${apt_args[@]}" "${packages[@]}"
}

verify_nvidia_upstream_repository() {
  local driver_policy=""
  local toolkit_policy=""
  driver_policy="$(apt-cache policy nvidia-driver)"
  toolkit_policy="$(apt-cache policy "$CUDA_TOOLKIT_PACKAGE")"
  grep -F 'developer.download.nvidia.com' <<<"$driver_policy" >/dev/null || die "nvidia-driver is not visible from the NVIDIA upstream repo"
  grep -F 'developer.download.nvidia.com' <<<"$toolkit_policy" >/dev/null || die "$CUDA_TOOLKIT_PACKAGE is not visible from the NVIDIA upstream repo"
}

install_debian_prerequisite_packages() {
  local -a packages=()
  mapfile -t packages < <(resolved_debian_prerequisite_packages)
  install_package_group "Debian prerequisite package set" "${packages[@]}"
}

install_optional_driver_pinning_package() {
  [[ -n "$NVIDIA_DRIVER_PIN_PACKAGE" ]] || return 0
  install_package_group "NVIDIA driver pinning package" "$NVIDIA_DRIVER_PIN_PACKAGE"
}

install_nvidia_stack() {
  [[ "${NVIDIA_INSTALL:-1}" == "1" ]] || die "set NVIDIA_INSTALL=1 to install NVIDIA packages"
  local -a driver_packages=()
  local -a toolkit_packages=()
  mapfile -t driver_packages < <(resolved_nvidia_driver_packages)
  mapfile -t toolkit_packages < <(resolved_cuda_toolkit_packages)
  install_package_group "NVIDIA driver package set" "${driver_packages[@]}"
  install_package_group "CUDA toolkit package set" "${toolkit_packages[@]}"
}

list_installed_packages_matching_patterns() {
  local -a patterns=( "$@" )
  local package=""
  while IFS= read -r package; do
    local pattern=""
    for pattern in "${patterns[@]}"; do
      case "$package" in
        $pattern)
          printf '%s\n' "$package"
          break
          ;;
      esac
    done
  done < <(dpkg-query -W -f='${Package}\n' 2>/dev/null | LC_ALL=C sort -u)
}

remove_packages_matching_patterns() {
  local label="$1"
  shift
  local -a apt_args=()
  local -a packages=()
  mapfile -t packages < <(list_installed_packages_matching_patterns "$@" | LC_ALL=C sort -u)
  if ((${#packages[@]} == 0)); then
    log_info "no installed packages matched ${label}"
    return 0
  fi
  mapfile -t apt_args < <(apt_yes_args)
  log_info "removing ${label}"
  run_mutating_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt-get remove --autoremove --purge -V "${apt_args[@]}" "${packages[@]}"
}

remove_nvidia_stack() {
  local -a patterns=()
  mapfile -t patterns < <(resolved_nvidia_removal_patterns)
  remove_packages_matching_patterns "NVIDIA/CUDA package anchors" "${patterns[@]}"
}
