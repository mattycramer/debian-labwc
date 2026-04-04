#!/usr/bin/env bash

readonly SYSTEM_DKMS_CONF_PATH="/etc/dkms/framework.conf.d/90-labwc-secure-boot.conf"
readonly SYSTEM_SIGN_MODULE_HELPER="/usr/local/bin/sign-module"

secure_boot_state() {
  local output=""

  if ! command -v mokutil >/dev/null 2>&1; then
    if [[ -d /sys/firmware/efi ]]; then
      printf '%s\n' "unknown"
    else
      printf '%s\n' "unavailable"
    fi
    return 0
  fi

  output="$(mokutil --sb-state 2>/dev/null || true)"
  case "${output,,}" in
    *secureboot\ enabled*)
      printf '%s\n' "enabled"
      ;;
    *secureboot\ disabled*)
      printf '%s\n' "disabled"
      ;;
    *)
      printf '%s\n' "unknown"
      ;;
  esac
}

verify_secure_boot_prerequisites() {
  local state=""

  state="$(secure_boot_state)"
  case "$state" in
    enabled)
      require_file "$SYSTEM_DKMS_CONF_PATH"
      [[ -x "$SYSTEM_SIGN_MODULE_HELPER" ]] || die "Secure Boot is enabled but '$SYSTEM_SIGN_MODULE_HELPER' is missing or not executable; run 00-system secureboot first"
      ;;
    unknown)
      log_warn "could not determine Secure Boot state; if UEFI Secure Boot is enabled, run 00-system secureboot before rebooting into the NVIDIA driver stack"
      ;;
  esac
}

locate_nvcc() {
  local candidate=""
  if command -v nvcc >/dev/null 2>&1; then
    command -v nvcc
    return 0
  fi
  if [[ -x "/usr/local/cuda/bin/nvcc" ]]; then
    printf '%s\n' "/usr/local/cuda/bin/nvcc"
    return 0
  fi
  for candidate in /usr/local/cuda-*/bin/nvcc; do
    [[ -x "$candidate" ]] || continue
    printf '%s\n' "$candidate"
    return 0
  done
  return 1
}

verify_installed_anchor_packages() {
  local package=""
  while IFS= read -r package; do
    [[ -n "$package" ]] || continue
    package_installed "$package" || die "required package '$package' is not installed"
  done < <(resolved_nvidia_anchor_packages)

  case "$NVIDIA_DRIVER_PIN_PACKAGE" in
    "")
      ;;
    auto)
      package="$(resolve_driver_pinning_package)" || die "unable to resolve the expected NVIDIA driver pinning package"
      package_installed "$package" || die "required package '$package' is not installed"
      ;;
    *)
      package_installed "$NVIDIA_DRIVER_PIN_PACKAGE" || die "required package '$NVIDIA_DRIVER_PIN_PACKAGE' is not installed"
      ;;
  esac
}

verify_driver_repository_visibility() {
  verify_nvidia_upstream_repository
}

verify_cuda_repository_sources() {
  local sources_path=""
  local legacy_path=""

  sources_path="$(cuda_repo_sources_path)"
  require_file "$sources_path"
  grep -Fx 'Types: deb' "$sources_path" >/dev/null || die "missing Types: deb in $sources_path"
  grep -Fx "URIs: $(cuda_repo_base_url)" "$sources_path" >/dev/null || die "unexpected NVIDIA upstream URI in $sources_path"
  grep -Fx 'Suites: /' "$sources_path" >/dev/null || die "missing Suites: / in $sources_path"
  grep -Fx 'Architectures: amd64' "$sources_path" >/dev/null || die "missing Architectures: amd64 in $sources_path"
  grep -Fx "Signed-By: ${CUDA_ARCHIVE_KEYRING_PATH}" "$sources_path" >/dev/null || die "unexpected Signed-By path in $sources_path"

  for legacy_path in /etc/apt/sources.list.d/cuda-*.list; do
    [[ -e "$legacy_path" ]] || continue
    die "legacy NVIDIA upstream repo file remains at $legacy_path; expected deb822 .sources only"
  done
}

verify_module_config() {
  if [[ "$NVIDIA_ENABLE_DRM_MODESET" == "1" ]]; then
    require_file "$NVIDIA_MODULE_CONFIG_PATH"
    grep -Fx 'options nvidia-drm modeset=1' "$NVIDIA_MODULE_CONFIG_PATH" >/dev/null || die "missing nvidia-drm modeset configuration"
  else
    [[ ! -e "$NVIDIA_MODULE_CONFIG_PATH" ]] || die "unexpected NVIDIA module config remains at $NVIDIA_MODULE_CONFIG_PATH"
  fi
}

verify_ihd_preservation() {
  local disallowed_setting=""

  if [[ "$NVIDIA_HAS_INTEL_MEDIA_DRIVER" == "yes" ]]; then
    package_installed intel-media-va-driver || die "intel-media-va-driver was present before install and should still be installed"
  fi
  if [[ -f "$NVIDIA_MODULE_CONFIG_PATH" ]]; then
    for disallowed_setting in \
      'LIBVA_DRIVER_NAME=' \
      'DRI_PRIME=' \
      '__NV_PRIME_RENDER_OFFLOAD=' \
      '__GLX_VENDOR_LIBRARY_NAME=' \
      'GBM_BACKEND='; do
      ! grep -F "$disallowed_setting" "$NVIDIA_MODULE_CONFIG_PATH" >/dev/null || die "managed NVIDIA config must not set $disallowed_setting globally"
    done
  fi
}

verify_cuda_toolkit() {
  local nvcc_path=""
  nvcc_path="$(locate_nvcc)" || die "nvcc was not found after installing $CUDA_TOOLKIT_PACKAGE"
  "$nvcc_path" --version >/dev/null 2>&1 || die "nvcc is present but failed to execute"
}

active_nvidia_drm_modeset() {
  local value=""

  [[ -r /sys/module/nvidia_drm/parameters/modeset ]] || return 1
  value="$(< /sys/module/nvidia_drm/parameters/modeset)"
  printf '%s\n' "${value//$'\n'/}"
}

verify_nvidia_drm_modeset_runtime() {
  local value=""

  [[ "$NVIDIA_ENABLE_DRM_MODESET" == "1" ]] || return 0
  value="$(active_nvidia_drm_modeset || true)"
  if [[ -z "$value" ]]; then
    log_warn "nvidia_drm is not loaded yet; reboot the system and rerun 'make verify' to confirm active DRM KMS state"
    return 0
  fi

  case "${value^^}" in
    Y|1) ;;
    *)
      die "nvidia_drm is loaded but DRM KMS modeset is not active (expected Y/1, got '$value')"
      ;;
  esac
}

verify_nvidia_runtime() {
  command -v nvidia-smi >/dev/null 2>&1 || die "nvidia-smi is missing after driver installation"
  if [[ -e /proc/driver/nvidia/version ]]; then
    nvidia-smi -L >/dev/null 2>&1 || die "nvidia-smi failed even though the NVIDIA kernel driver appears to be loaded"
    return 0
  fi
  log_warn "NVIDIA kernel modules are not active yet; reboot the system and rerun 'make verify' for runtime validation"
}

trim_switcheroo_field() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  printf '%s\n' "$value"
}

verify_switcheroo_setup() {
  local output=""
  local line=""
  local current_name=""
  local current_default=""
  local current_discrete=""
  local current_environment=""
  local saw_nvidia="no"
  local saw_intel="no"
  local saw_integrated_default="no"
  local saw_discrete_offload="no"

  if [[ "$NVIDIA_INSTALL_SWITCHEROO_CONTROL" != "1" ]]; then
    return 0
  fi
  package_installed switcheroo-control || die "switcheroo-control is not installed"
  command -v switcherooctl >/dev/null 2>&1 || die "switcherooctl command is missing"
  output="$(switcherooctl list 2>/dev/null || true)"
  [[ -n "$output" ]] || die "switcherooctl list returned no GPU data"

  while IFS= read -r line; do
    case "$line" in
      Device:*)
        current_name=""
        current_default=""
        current_discrete=""
        current_environment=""
        ;;
      "  Name:"*)
        current_name="$(trim_switcheroo_field "${line#  Name:}")"
        ;;
      "  Default:"*)
        current_default="$(trim_switcheroo_field "${line#  Default:}")"
        current_default="${current_default,,}"
        ;;
      "  Discrete:"*)
        current_discrete="$(trim_switcheroo_field "${line#  Discrete:}")"
        current_discrete="${current_discrete,,}"
        ;;
      "  Environment:"*)
        current_environment="$(trim_switcheroo_field "${line#  Environment:}")"
        if [[ "${current_name,,}" == *nvidia* || "$current_discrete" == "yes" ]]; then
          saw_nvidia="yes"
        fi
        if [[ "${current_name,,}" == *intel* || "$current_discrete" == "no" ]]; then
          saw_intel="yes"
          if [[ "$current_default" == "yes" ]]; then
            saw_integrated_default="yes"
          fi
        fi
        if [[ "$current_discrete" == "yes" ]]; then
          case "$current_environment" in
            *DRI_PRIME=*|*__NV_PRIME_RENDER_OFFLOAD=1*|*__GLX_VENDOR_LIBRARY_NAME=nvidia*)
              saw_discrete_offload="yes"
              ;;
          esac
        fi
        ;;
    esac
  done <<<"$output"

  [[ "$saw_nvidia" == "yes" ]] || die "switcherooctl did not report an NVIDIA GPU"
  [[ "$saw_discrete_offload" == "yes" ]] || die "switcherooctl did not expose a PRIME offload selector for the discrete GPU"
  if [[ "$NVIDIA_HAS_INTEL_GPU" == "yes" ]]; then
    [[ "$saw_intel" == "yes" ]] || die "switcherooctl did not report an Intel integrated GPU"
    [[ "$saw_integrated_default" == "yes" ]] || die "switcherooctl did not report the integrated GPU as the default renderer"
  fi
}

verify_installation() {
  verify_driver_repository_visibility
  verify_cuda_repository_sources
  verify_installed_anchor_packages
  verify_module_config
  verify_ihd_preservation
  verify_cuda_toolkit
  verify_nvidia_drm_modeset_runtime
  verify_switcheroo_setup
  verify_nvidia_runtime
}
