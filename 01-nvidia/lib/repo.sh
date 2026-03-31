#!/usr/bin/env bash

cuda_repo_base_url() {
  printf 'https://developer.download.nvidia.com/compute/cuda/repos/%s/%s\n' "$NVIDIA_REPO_DISTRO" "$NVIDIA_REPO_ARCH_PATH"
}

cuda_keyring_deb_url() {
  printf '%s/cuda-keyring_1.1-1_all.deb\n' "$(cuda_repo_base_url)"
}

ensure_download_tool() {
  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    return 0
  fi
  log_warn "neither curl nor wget is installed; bootstrapping wget from Debian repositories"
  install_package_group "download bootstrap" ca-certificates wget
}

download_file() {
  local url="$1"
  local destination="$2"
  local attempt=1

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    log_info "dry-run: download $url -> $destination"
    return 0
  fi

  while true; do
    if command -v curl >/dev/null 2>&1; then
      if curl --fail --location --silent --show-error --max-time 30 --output "$destination" "$url"; then
        break
      fi
    elif command -v wget >/dev/null 2>&1; then
      if wget -q -T 30 -O "$destination" "$url"; then
        break
      fi
    else
      die "no supported download tool is available"
    fi

    if (( attempt >= 3 )); then
      die "failed to download '$url' after ${attempt} attempts"
    fi
    sleep "$attempt"
    attempt=$((attempt + 1))
  done

  [[ -s "$destination" ]] || die "downloaded file is empty: $destination"
}

render_debian_components_sources() {
  cat <<EOF
Types: deb
URIs: https://deb.debian.org/debian
Suites: ${HOST_DEBIAN_CODENAME} ${NVIDIA_DEBIAN_UPDATES_SUITE}
Components: contrib
Architectures: amd64
Signed-By: ${DEBIAN_ARCHIVE_KEYRING_PATH}

Types: deb
URIs: https://security.debian.org/debian-security
Suites: ${NVIDIA_DEBIAN_SECURITY_SUITE}
Components: contrib
Architectures: amd64
Signed-By: ${DEBIAN_ARCHIVE_KEYRING_PATH}
EOF
}

ensure_debian_components_sources() {
  local content=""
  content="$(render_debian_components_sources)"
  run_mutating_cmd install -D -m 0644 /dev/null "$DEBIAN_COMPONENTS_SOURCE_PATH"
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    log_info "dry-run: write $DEBIAN_COMPONENTS_SOURCE_PATH"
    return 0
  fi
  printf '%s\n' "$content" >"$DEBIAN_COMPONENTS_SOURCE_PATH"
}

remove_debian_components_sources() {
  if [[ -f "$DEBIAN_COMPONENTS_SOURCE_PATH" ]]; then
    run_mutating_cmd rm -f "$DEBIAN_COMPONENTS_SOURCE_PATH"
  fi
}

install_cuda_keyring_package() {
  local temp_dir=""
  local deb_path=""
  temp_dir="$(mktemp -d)"
  deb_path="$temp_dir/cuda-keyring_1.1-1_all.deb"
  download_file "$(cuda_keyring_deb_url)" "$deb_path"
  run_mutating_cmd dpkg -i "$deb_path"
  if [[ "${DRY_RUN:-0}" -ne 1 ]]; then
    rm -rf -- "$temp_dir"
  fi
}

remove_cuda_keyring_package() {
  if package_installed cuda-keyring; then
    remove_packages_matching_patterns "cuda-keyring" cuda-keyring
  fi
}
