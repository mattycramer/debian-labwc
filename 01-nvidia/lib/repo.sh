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

debian_sources_deb822_have_contrib() {
  local source_path="$1"

  [[ -r "$source_path" ]] || return 1
  awk '
    BEGIN {
      RS = ""
      FS = "\n"
    }
    {
      uri_ok = 0
      contrib_ok = 0
      for (i = 1; i <= NF; i++) {
        line = $i
        sub(/\r$/, "", line)
        if (line ~ /^[[:space:]]*#/) {
          continue
        }
        if (line ~ /^URIs:[[:space:]]*/ &&
            (line ~ /deb\.debian\.org\/debian/ || line ~ /security\.debian\.org\/debian-security/)) {
          uri_ok = 1
        }
        if (line ~ /^Components:[[:space:]]*/ &&
            line ~ /(^|[[:space:]])contrib([[:space:]]|$)/) {
          contrib_ok = 1
        }
      }
      if (uri_ok && contrib_ok) {
        found = 1
      }
    }
    END {
      exit(found ? 0 : 1)
    }
  ' "$source_path"
}

debian_sources_list_have_contrib() {
  local source_path="$1"

  [[ -r "$source_path" ]] || return 1
  awk '
    /^[[:space:]]*#/ {
      next
    }
    /^[[:space:]]*deb([[:space:]]+\[[^]]*\])?[[:space:]]+/ {
      if (($0 ~ /deb\.debian\.org\/debian/ || $0 ~ /security\.debian\.org\/debian-security/) &&
          $0 ~ /(^|[[:space:]])contrib([[:space:]]|$)/) {
        found = 1
      }
    }
    END {
      exit(found ? 0 : 1)
    }
  ' "$source_path"
}

debian_contrib_configured() {
  local source_path=""

  if debian_sources_list_have_contrib "/etc/apt/sources.list"; then
    return 0
  fi

  for source_path in /etc/apt/sources.list.d/*; do
    [[ -e "$source_path" ]] || continue
    case "$source_path" in
      *.sources)
        if debian_sources_deb822_have_contrib "$source_path"; then
          return 0
        fi
        ;;
      *.list)
        if debian_sources_list_have_contrib "$source_path"; then
          return 0
        fi
        ;;
    esac
  done

  return 1
}

require_debian_contrib_configured() {
  debian_contrib_configured && return 0
  die "Debian contrib is not configured in the existing apt sources. 01-nvidia will not write Debian archive files; enable contrib yourself and rerun the installer."
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
