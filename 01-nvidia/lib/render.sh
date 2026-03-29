#!/usr/bin/env bash

readonly NVIDIA_MODULE_CONFIG_PATH="/etc/modprobe.d/debian-labwc-nvidia.conf"

render_nvidia_module_config() {
  local content=""
  if [[ "$NVIDIA_ENABLE_DRM_MODESET" != "1" ]]; then
    remove_nvidia_module_config
    return 0
  fi

  content="$(cat <<'EOF'
# Managed by debian-labwc 01-nvidia
# Keep Intel/iHD as the default render/video path. This only enables DRM KMS
# for NVIDIA so Wayland compositors and switcherooctl offload work correctly.
options nvidia-drm modeset=1
EOF
)"
  run_mutating_cmd install -D -m 0644 /dev/null "$NVIDIA_MODULE_CONFIG_PATH"
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    log_info "dry-run: write $NVIDIA_MODULE_CONFIG_PATH"
    return 0
  fi
  printf '%s\n' "$content" >"$NVIDIA_MODULE_CONFIG_PATH"
}

remove_nvidia_module_config() {
  if [[ -f "$NVIDIA_MODULE_CONFIG_PATH" ]]; then
    run_mutating_cmd rm -f "$NVIDIA_MODULE_CONFIG_PATH"
  fi
}

refresh_initramfs() {
  require_command update-initramfs
  run_mutating_cmd update-initramfs -u
}
