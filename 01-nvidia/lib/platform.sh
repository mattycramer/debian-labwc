#!/usr/bin/env bash

readonly DEBIAN_ARCHIVE_KEYRING_PATH="/usr/share/keyrings/debian-archive-keyring.gpg"
readonly DEBIAN_COMPONENTS_SOURCE_PATH="/etc/apt/sources.list.d/labwc-nvidia-debian.sources"
readonly NVIDIA_VENDOR_HEX="0x10de"
readonly INTEL_VENDOR_HEX="0x8086"

debian_codename() {
  local codename=""
  # shellcheck disable=SC1091
  . /etc/os-release
  codename="${VERSION_CODENAME:-}"
  printf '%s' "$codename"
}

debian_version_id() {
  local version_id=""
  # shellcheck disable=SC1091
  . /etc/os-release
  version_id="${VERSION_ID:-}"
  printf '%s' "$version_id"
}

gpu_vendor_present() {
  local vendor_hex="$1"
  local path=""
  local class=""
  local vendor=""
  for path in /sys/bus/pci/devices/*; do
    [[ -r "$path/class" && -r "$path/vendor" ]] || continue
    class="$(<"$path/class")"
    vendor="$(<"$path/vendor")"
    case "$class" in
      0x030000|0x030200)
        [[ "$vendor" == "$vendor_hex" ]] && return 0
        ;;
    esac
  done
  return 1
}

intel_media_driver_installed() {
  package_installed intel-media-va-driver
}

resolve_nvidia_repo_distro() {
  case "$NVIDIA_UPSTREAM_DISTRO" in
    auto)
      case "$HOST_DEBIAN_CODENAME" in
        bookworm) printf '%s' "debian12" ;;
        trixie) printf '%s' "debian13" ;;
        *)
          die "no automatic NVIDIA upstream repo mapping for host codename '$HOST_DEBIAN_CODENAME'"
          ;;
      esac
      ;;
    debian12)
      case "$HOST_DEBIAN_CODENAME" in
        bookworm|trixie) printf '%s' "debian12" ;;
        *)
          die "NVIDIA_UPSTREAM_DISTRO=debian12 is only supported on Debian bookworm or trixie hosts"
          ;;
      esac
      ;;
    debian13)
      [[ "$HOST_DEBIAN_CODENAME" == "trixie" ]] || die "NVIDIA_UPSTREAM_DISTRO=debian13 requires a Debian trixie host"
      printf '%s' "debian13"
      ;;
    *)
      die "unsupported NVIDIA_UPSTREAM_DISTRO '$NVIDIA_UPSTREAM_DISTRO'"
      ;;
  esac
}

validate_config() {
  require_boolean_setting "NVIDIA_INSTALL" "$NVIDIA_INSTALL"
  require_value_in_set "NVIDIA_UPSTREAM_DISTRO" "$NVIDIA_UPSTREAM_DISTRO" auto debian12 debian13
  require_value_in_set "NVIDIA_KERNEL_MODULE_FLAVOR" "$NVIDIA_KERNEL_MODULE_FLAVOR" proprietary open
  require_boolean_setting "NVIDIA_INSTALL_SWITCHEROO_CONTROL" "$NVIDIA_INSTALL_SWITCHEROO_CONTROL"
  require_boolean_setting "NVIDIA_ENABLE_DRM_MODESET" "$NVIDIA_ENABLE_DRM_MODESET"
  if [[ -n "$NVIDIA_DRIVER_PIN_PACKAGE" && "$NVIDIA_DRIVER_PIN_PACKAGE" != "auto" ]]; then
    require_regex_match "NVIDIA_DRIVER_PIN_PACKAGE" "$NVIDIA_DRIVER_PIN_PACKAGE" '^nvidia-driver-pinning-[A-Za-z0-9][A-Za-z0-9._-]*$'
  fi
  require_regex_match "CUDA_TOOLKIT_PACKAGE" "$CUDA_TOOLKIT_PACKAGE" '^cuda-toolkit(-[0-9]+){0,2}$'
}

resolve_platform_config() {
  HOST_DEBIAN_CODENAME="$(debian_codename)"
  HOST_DEBIAN_VERSION_ID="$(debian_version_id)"
  NVIDIA_REPO_DISTRO="$(resolve_nvidia_repo_distro)"
  NVIDIA_REPO_ARCH_PATH="x86_64"
  NVIDIA_HAS_NVIDIA_GPU="no"
  NVIDIA_HAS_INTEL_GPU="no"
  NVIDIA_HAS_INTEL_MEDIA_DRIVER="no"
  NVIDIA_CURRENT_KERNEL_HEADERS_PACKAGE="linux-headers-$(uname -r)"
  NVIDIA_DEBIAN_UPDATES_SUITE="${HOST_DEBIAN_CODENAME}-updates"
  NVIDIA_DEBIAN_SECURITY_SUITE="${HOST_DEBIAN_CODENAME}-security"
  NVIDIA_DRIVER_META_PACKAGE=""

  if gpu_vendor_present "$NVIDIA_VENDOR_HEX"; then
    NVIDIA_HAS_NVIDIA_GPU="yes"
  fi
  if gpu_vendor_present "$INTEL_VENDOR_HEX"; then
    NVIDIA_HAS_INTEL_GPU="yes"
  fi
  if intel_media_driver_installed; then
    NVIDIA_HAS_INTEL_MEDIA_DRIVER="yes"
  fi

  case "$NVIDIA_KERNEL_MODULE_FLAVOR" in
    proprietary)
      NVIDIA_DRIVER_META_PACKAGE="cuda-drivers"
      ;;
    open)
      NVIDIA_DRIVER_META_PACKAGE="nvidia-open"
      ;;
    *)
      die "unsupported NVIDIA_KERNEL_MODULE_FLAVOR '$NVIDIA_KERNEL_MODULE_FLAVOR'"
      ;;
  esac
}

log_platform_summary() {
  log_info "host Debian ${HOST_DEBIAN_VERSION_ID:-unknown} (${HOST_DEBIAN_CODENAME:-unknown}), NVIDIA upstream repo ${NVIDIA_REPO_DISTRO}, kernel module flavor ${NVIDIA_KERNEL_MODULE_FLAVOR}"
  log_info "GPU detection: NVIDIA=${NVIDIA_HAS_NVIDIA_GPU}, Intel=${NVIDIA_HAS_INTEL_GPU}, intel-media-va-driver=${NVIDIA_HAS_INTEL_MEDIA_DRIVER}"
  if [[ "$HOST_DEBIAN_CODENAME" == "trixie" && "$NVIDIA_REPO_DISTRO" == "debian12" ]]; then
    log_warn "using the Debian 12 NVIDIA upstream repo on a Debian 13 host because NVIDIA_UPSTREAM_DISTRO was forced to debian12"
  fi
}

print_resolved_config() {
  cat <<EOF
NVIDIA_INSTALL=${NVIDIA_INSTALL}
NVIDIA_UPSTREAM_DISTRO=${NVIDIA_UPSTREAM_DISTRO}
NVIDIA_REPO_DISTRO=${NVIDIA_REPO_DISTRO}
NVIDIA_KERNEL_MODULE_FLAVOR=${NVIDIA_KERNEL_MODULE_FLAVOR}
NVIDIA_DRIVER_META_PACKAGE=${NVIDIA_DRIVER_META_PACKAGE}
NVIDIA_DRIVER_PIN_PACKAGE=${NVIDIA_DRIVER_PIN_PACKAGE}
CUDA_TOOLKIT_PACKAGE=${CUDA_TOOLKIT_PACKAGE}
NVIDIA_INSTALL_SWITCHEROO_CONTROL=${NVIDIA_INSTALL_SWITCHEROO_CONTROL}
NVIDIA_ENABLE_DRM_MODESET=${NVIDIA_ENABLE_DRM_MODESET}
HOST_DEBIAN_CODENAME=${HOST_DEBIAN_CODENAME}
HOST_DEBIAN_VERSION_ID=${HOST_DEBIAN_VERSION_ID}
NVIDIA_HAS_NVIDIA_GPU=${NVIDIA_HAS_NVIDIA_GPU}
NVIDIA_HAS_INTEL_GPU=${NVIDIA_HAS_INTEL_GPU}
NVIDIA_HAS_INTEL_MEDIA_DRIVER=${NVIDIA_HAS_INTEL_MEDIA_DRIVER}
NVIDIA_CURRENT_KERNEL_HEADERS_PACKAGE=${NVIDIA_CURRENT_KERNEL_HEADERS_PACKAGE}
EOF
}

resolved_debian_prerequisite_packages() {
  printf '%s\n' \
    build-essential \
    ca-certificates \
    dkms \
    initramfs-tools \
    "$NVIDIA_CURRENT_KERNEL_HEADERS_PACKAGE" \
    linux-headers-amd64 \
    pciutils
  if [[ "$NVIDIA_INSTALL_SWITCHEROO_CONTROL" == "1" ]]; then
    printf '%s\n' \
      mesa-utils \
      vulkan-tools
  fi
}

resolved_sid_prerequisite_packages() {
  if [[ "$NVIDIA_INSTALL_SWITCHEROO_CONTROL" == "1" ]]; then
    printf '%s\n' \
      switcheroo-control
  fi
}

resolved_nvidia_driver_packages() {
  printf '%s\n' "$NVIDIA_DRIVER_META_PACKAGE"
}

resolved_cuda_toolkit_packages() {
  printf '%s\n' "$CUDA_TOOLKIT_PACKAGE"
}

resolved_nvidia_anchor_packages() {
  resolved_nvidia_driver_packages
  resolved_cuda_toolkit_packages
  if [[ -n "$NVIDIA_DRIVER_PIN_PACKAGE" && "$NVIDIA_DRIVER_PIN_PACKAGE" != "auto" ]]; then
    printf '%s\n' "$NVIDIA_DRIVER_PIN_PACKAGE"
  fi
  printf '%s\n' cuda-keyring
}

resolved_nvidia_removal_patterns() {
  printf '%s\n' \
    cuda-keyring \
    cuda-drivers \
    'cuda-drivers-*' \
    cuda-toolkit \
    'cuda-toolkit-*' \
    nvidia-open \
    'nvidia-open-*' \
    nvidia-driver \
    nvidia-driver-cuda \
    nvidia-kernel-dkms \
    nvidia-kernel-open-dkms \
    'nvidia-driver-pinning-*'
}
