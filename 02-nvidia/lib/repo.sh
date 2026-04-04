#!/usr/bin/env bash

readonly CUDA_ARCHIVE_KEYRING_PATH="/usr/share/keyrings/cuda-archive-keyring.gpg"

cuda_repo_base_url() {
  printf 'https://developer.download.nvidia.com/compute/cuda/repos/%s/%s\n' "$NVIDIA_REPO_DISTRO" "$NVIDIA_REPO_ARCH_PATH"
}

cuda_repo_sources_path() {
  printf '/etc/apt/sources.list.d/cuda-%s-%s.sources\n' "$NVIDIA_REPO_DISTRO" "$NVIDIA_REPO_ARCH_PATH"
}

fetch_url_to_stdout() {
  local url="$1"
  local attempt=1

  while true; do
    if command -v curl >/dev/null 2>&1; then
      if curl --fail --location --silent --show-error --max-time 30 "$url"; then
        return 0
      fi
    elif command -v wget >/dev/null 2>&1; then
      if wget -q -T 30 -O - "$url"; then
        return 0
      fi
    else
      die "no supported download tool is available"
    fi

    if (( attempt >= 3 )); then
      die "failed to fetch '$url' after ${attempt} attempts"
    fi
    sleep "$attempt"
    attempt=$((attempt + 1))
  done
}

resolve_cuda_keyring_filename() {
  local candidate=""
  local candidate_version=""
  local selected_filename=""
  local selected_version=""

  while IFS= read -r candidate; do
    [[ "$candidate" =~ ^cuda-keyring_[A-Za-z0-9.+:~_-]+_all\.deb$ ]] || continue
    candidate_version="${candidate#cuda-keyring_}"
    candidate_version="${candidate_version%_all.deb}"
    if [[ -z "$selected_version" ]] || dpkg --compare-versions "$candidate_version" gt "$selected_version"; then
      selected_version="$candidate_version"
      selected_filename="$candidate"
    fi
  done < <(
    fetch_url_to_stdout "$(cuda_repo_base_url)/" |
      grep -Eo 'cuda-keyring_[A-Za-z0-9.+:~_-]+_all\.deb' |
      LC_ALL=C sort -u
  )

  [[ -n "$selected_filename" ]] || die "failed to resolve the current upstream cuda-keyring package from $(cuda_repo_base_url)/"
  printf '%s\n' "$selected_filename"
}

cuda_keyring_deb_url() {
  local filename=""
  filename="$(resolve_cuda_keyring_filename)"
  printf '%s/%s\n' "$(cuda_repo_base_url)" "$filename"
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
  die "Debian contrib is not configured in the existing apt sources. 02-nvidia will not write Debian archive files; enable contrib yourself and rerun the installer."
}

render_cuda_repository_sources() {
  cat <<EOF
Types: deb
URIs: $(cuda_repo_base_url)
Suites: /
Architectures: amd64
Signed-By: ${CUDA_ARCHIVE_KEYRING_PATH}
EOF
}

remove_cuda_repository_source_files() {
  local expected_path="${1:-}"
  local source_path=""

  for source_path in /etc/apt/sources.list.d/cuda-*.list /etc/apt/sources.list.d/cuda-*.sources; do
    [[ -e "$source_path" ]] || continue
    if [[ -n "$expected_path" && "$source_path" == "$expected_path" ]]; then
      continue
    fi
    run_mutating_cmd rm -f "$source_path"
  done
}

ensure_cuda_repository_sources_normalized() {
  local sources_path=""
  local content=""

  sources_path="$(cuda_repo_sources_path)"
  content="$(render_cuda_repository_sources)"

  if [[ "${DRY_RUN:-0}" -ne 1 ]]; then
    require_file "$CUDA_ARCHIVE_KEYRING_PATH"
  fi

  remove_cuda_repository_source_files "$sources_path"
  run_mutating_cmd install -D -m 0644 /dev/null "$sources_path"
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    log_info "dry-run: write $sources_path"
    return 0
  fi
  printf '%s\n' "$content" >"$sources_path"
}

install_cuda_keyring_package() {
  local temp_dir=""
  local deb_path=""
  local keyring_filename=""
  temp_dir="$(mktemp -d)"
  keyring_filename="$(resolve_cuda_keyring_filename)"
  deb_path="$temp_dir/$keyring_filename"
  log_info "using upstream CUDA keyring package ${keyring_filename}"
  download_file "$(cuda_repo_base_url)/${keyring_filename}" "$deb_path"
  run_mutating_cmd dpkg -i "$deb_path"
  ensure_cuda_repository_sources_normalized
  if [[ "${DRY_RUN:-0}" -ne 1 ]]; then
    rm -rf -- "$temp_dir"
  fi
}

remove_cuda_keyring_package() {
  remove_cuda_repository_source_files
  if package_installed cuda-keyring; then
    remove_packages_matching_patterns "cuda-keyring" cuda-keyring
  fi
}
