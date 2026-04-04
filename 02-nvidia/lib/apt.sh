#!/usr/bin/env bash

readonly SID_SUITE="sid"

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

package_available() {
  apt-cache show "$1" >/dev/null 2>&1
}

apt_candidate_version() {
  local package_name="$1"
  apt-cache policy "$package_name" | awk '/Candidate:/ { print $2; exit }'
}

apt_target_candidate_version() {
  local suite="$1"
  local package_name="$2"
  apt-cache -o APT::Default-Release="$suite" policy "$package_name" | awk '/Candidate:/ { print $2; exit }'
}

resolve_driver_pinning_package() {
  local candidate_version=""
  local driver_version=""
  local selected_package=""
  local major_branch=""

  case "$NVIDIA_DRIVER_PIN_PACKAGE" in
    "")
      return 1
      ;;
    auto)
      candidate_version="$(apt_candidate_version "$NVIDIA_DRIVER_META_PACKAGE")"
      [[ -n "$candidate_version" && "$candidate_version" != "(none)" ]] || die "unable to determine the candidate version for $NVIDIA_DRIVER_META_PACKAGE"
      driver_version="${candidate_version%%-*}"
      selected_package="nvidia-driver-pinning-${driver_version}"
      if ! package_available "$selected_package"; then
        major_branch="${driver_version%%.*}"
        selected_package="nvidia-driver-pinning-${major_branch}"
        package_available "$selected_package" || die "unable to resolve a matching NVIDIA driver pinning package for $NVIDIA_DRIVER_META_PACKAGE candidate version $candidate_version"
      fi
      ;;
    *)
      selected_package="$NVIDIA_DRIVER_PIN_PACKAGE"
      package_available "$selected_package" || die "requested pinning package '$selected_package' is not available from the configured repositories"
      ;;
  esac

  printf '%s\n' "$selected_package"
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
  local package_name=""
  local selected_package=""

  while IFS= read -r package_name; do
    [[ -n "$package_name" ]] || continue
    verify_package_visible_from_origin "$package_name" "developer.download.nvidia.com"
  done < <(resolved_nvidia_upstream_packages)

  selected_package="$(resolve_driver_pinning_package)" || true
  if [[ -n "$selected_package" ]]; then
    verify_package_visible_from_origin "$selected_package" "developer.download.nvidia.com"
  fi
}

install_debian_prerequisite_packages() {
  local -a packages=()
  mapfile -t packages < <(resolved_debian_prerequisite_packages)
  install_sid_package_group "sid prerequisite package set" "${packages[@]}"
}

verify_package_visible_from_origin() {
  local package_name="$1"
  local origin="$2"
  local policy=""

  policy="$(apt-cache policy "$package_name" 2>/dev/null || true)"
  [[ -n "$policy" ]] || die "apt-cache policy returned no output for '$package_name'"
  grep -F "$origin" <<<"$policy" >/dev/null || die "$package_name is not visible from $origin"
}

verify_package_visible_from_target_release() {
  local package_name="$1"
  local suite="$2"
  local candidate=""

  candidate="$(apt_target_candidate_version "$suite" "$package_name")"
  [[ -n "$candidate" && "$candidate" != "(none)" ]] || die "$package_name is not available from apt target '$suite'; ensure 00-system has already configured the sid archive before running 02-nvidia"
}

verify_sid_prerequisite_repository() {
  verify_package_visible_from_target_release build-essential "$SID_SUITE"
  verify_package_visible_from_target_release dkms "$SID_SUITE"
  if [[ "$NVIDIA_INSTALL_SWITCHEROO_CONTROL" == "1" ]]; then
    verify_package_visible_from_target_release switcheroo-control "$SID_SUITE"
  fi
}

install_sid_package_group() {
  local label="$1"
  shift
  local -a apt_args=()
  local -a packages=( "$@" )
  if ((${#packages[@]} == 0)); then
    return 0
  fi
  mapfile -t apt_args < <(apt_yes_args)
  log_info "installing ${label}"
  run_mutating_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt -t "$SID_SUITE" install -V --no-install-recommends "${apt_args[@]}" "${packages[@]}"
}

install_optional_driver_pinning_package() {
  local selected_package=""
  selected_package="$(resolve_driver_pinning_package)" || return 0
  install_package_group "NVIDIA driver pinning package" "$selected_package"
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
