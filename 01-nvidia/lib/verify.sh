#!/usr/bin/env bash

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
}

verify_driver_repository_visibility() {
  verify_nvidia_upstream_repository
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
  if [[ "$NVIDIA_HAS_INTEL_MEDIA_DRIVER" == "yes" ]]; then
    package_installed intel-media-va-driver || die "intel-media-va-driver was present before install and should still be installed"
  fi
  if [[ -f "$NVIDIA_MODULE_CONFIG_PATH" ]]; then
    ! grep -F 'LIBVA_DRIVER_NAME=nvidia' "$NVIDIA_MODULE_CONFIG_PATH" >/dev/null || die "managed NVIDIA config must not override LIBVA_DRIVER_NAME"
  fi
}

verify_cuda_toolkit() {
  local nvcc_path=""
  nvcc_path="$(locate_nvcc)" || die "nvcc was not found after installing $CUDA_TOOLKIT_PACKAGE"
  "$nvcc_path" --version >/dev/null 2>&1 || die "nvcc is present but failed to execute"
}

verify_nvidia_runtime() {
  command -v nvidia-smi >/dev/null 2>&1 || die "nvidia-smi is missing after driver installation"
  if [[ -e /proc/driver/nvidia/version ]]; then
    nvidia-smi -L >/dev/null 2>&1 || die "nvidia-smi failed even though the NVIDIA kernel driver appears to be loaded"
    return 0
  fi
  log_warn "NVIDIA kernel modules are not active yet; reboot the system and rerun 'make verify' for runtime validation"
}

verify_switcheroo_setup() {
  local output=""
  if [[ "$NVIDIA_INSTALL_SWITCHEROO_CONTROL" != "1" ]]; then
    return 0
  fi
  package_installed switcheroo-control || die "switcheroo-control is not installed"
  command -v switcherooctl >/dev/null 2>&1 || die "switcherooctl command is missing"
  output="$(switcherooctl list 2>/dev/null || true)"
  [[ -n "$output" ]] || die "switcherooctl list returned no GPU data"
  grep -E 'NVIDIA|10de' <<<"$output" >/dev/null || die "switcherooctl did not report an NVIDIA GPU"
  grep -F '__GLX_VENDOR_LIBRARY_NAME=nvidia' <<<"$output" >/dev/null || die "switcherooctl did not expose NVIDIA PRIME offload environment variables"
}

verify_installation() {
  verify_driver_repository_visibility
  verify_installed_anchor_packages
  verify_module_config
  verify_ihd_preservation
  verify_cuda_toolkit
  verify_switcheroo_setup
  verify_nvidia_runtime
}
