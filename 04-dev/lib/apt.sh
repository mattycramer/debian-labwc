#!/usr/bin/env bash

readonly BOOTSTRAP_PACKAGES=(
  ca-certificates
  curl
  xz-utils
)

readonly DEV_PACKAGES=(
  nmap
  strace
  lsof
  net-tools
  iproute2
  jq
  yamllint
  valgrind
  linux-perf
  pipx
  pkg-config
  htop
)

retry_cmd() {
  local attempts="$1"
  shift
  local try=1
  while true; do
    if run_cmd "$@"; then
      return 0
    fi
    if ((try >= attempts)); then
      return 1
    fi
    sleep "$try"
    try=$((try + 1))
  done
}

apt_yes_args() {
  if [[ "${ASSUME_YES:-1}" -eq 1 ]]; then
    printf '%s\n' "-y"
  fi
}

apt_update() {
  retry_cmd 3 env DEBIAN_FRONTEND=noninteractive apt update -o Acquire::Retries=3 -o Acquire::http::Timeout=20
}

install_bootstrap_packages() {
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive apt install --no-install-recommends "${apt_args[@]}" "${BOOTSTRAP_PACKAGES[@]}"
}

install_dev_packages() {
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive apt install --no-install-recommends "${apt_args[@]}" "${DEV_PACKAGES[@]}"
}

resolve_node_release() {
  local shasums_url="${NODE_DIST_BASE}/SHASUMS256.txt"
  local shasums_file
  shasums_file="$(mktemp)"
  curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 120 --silent --show-error -o "$shasums_file" "$shasums_url"
  local line
  line="$(awk '/ node-v[0-9]+\.[0-9]+\.[0-9]+-linux-x64\.tar\.xz$/ {print $1, $2; exit}' "$shasums_file")"
  rm -f -- "$shasums_file"
  [[ -n "$line" ]] || die "could not resolve latest Node.js ${NODE_MAJOR}.x release"
  NODE_SHA256="${line%% *}"
  NODE_TARBALL="${line#* }"
  NODE_DIRNAME="${NODE_TARBALL%.tar.xz}"
  NODE_VERSION="${NODE_DIRNAME#node-v}"
  NODE_VERSION="${NODE_VERSION%-linux-x64}"
  export NODE_SHA256 NODE_TARBALL NODE_DIRNAME NODE_VERSION
}

install_node_runtime() {
  resolve_node_release

  local install_dir="${NODE_INSTALL_ROOT}/${NODE_DIRNAME}"
  local current_link="${NODE_INSTALL_ROOT}/current"
  local tmpdir
  local tarball_path

  run_cmd install -d -m 0755 "$NODE_INSTALL_ROOT"
  run_cmd install -d -m 0755 /usr/local/bin

  if [[ ! -x "$install_dir/bin/node" ]]; then
    tmpdir="$(mktemp -d)"
    tarball_path="${tmpdir}/${NODE_TARBALL}"
    run_cmd curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 300 --silent --show-error -o "$tarball_path" "${NODE_DIST_BASE}/${NODE_TARBALL}"
    if [[ "${DRY_RUN:-0}" -eq 0 ]]; then
      local actual_sha
      actual_sha="$(sha256sum "$tarball_path" | awk '{print $1}')"
      [[ "$actual_sha" == "$NODE_SHA256" ]] || die "Node.js tarball checksum mismatch for ${NODE_TARBALL}"
    fi
    run_cmd tar -xJf "$tarball_path" -C "$tmpdir"
    run_cmd rm -rf -- "$install_dir"
    run_cmd mv -- "${tmpdir}/${NODE_DIRNAME}" "$install_dir"
    run_cmd rm -rf -- "$tmpdir"
  fi

  run_cmd ln -sfn "$install_dir" "$current_link"
  run_cmd ln -sfn "${current_link}/bin/node" /usr/local/bin/node
  run_cmd ln -sfn "${current_link}/bin/npm" /usr/local/bin/npm
  run_cmd ln -sfn "${current_link}/bin/npx" /usr/local/bin/npx
  run_cmd rm -f "${current_link}/bin/corepack" "${current_link}/bin/pnpm" "${current_link}/bin/pnpx"
  run_cmd rm -rf "${current_link}/lib/node_modules/corepack" "${current_link}/lib/node_modules/pnpm"
  run_cmd "${current_link}/bin/npm" --prefix "$current_link" install --global "$COREPACK_NPM_SPEC"
  run_cmd ln -sfn "${current_link}/bin/corepack" /usr/local/bin/corepack
  run_cmd "${current_link}/bin/npm" --prefix "$current_link" install --global "$PNPM_NPM_SPEC"
  run_cmd ln -sfn "${current_link}/bin/pnpm" /usr/local/bin/pnpm
  run_cmd ln -sfn "${current_link}/bin/pnpx" /usr/local/bin/pnpx
}

package_is_installed() {
  dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null | grep -F "install ok installed" >/dev/null
}

command_is_available() {
  command -v "$1" >/dev/null 2>&1
}

verify_node_runtime() {
  local node_version
  local node_major
  node_version="$(node --version 2>/dev/null | sed 's/^v//')"
  [[ -n "$node_version" ]] || die "node is not installed"
  node_major="${node_version%%.*}"
  [[ "$node_major" =~ ^[0-9]+$ ]] || die "could not parse node major version from '$node_version'"
  ((node_major >= NODE_MAJOR)) || die "expected Node.js ${NODE_MAJOR}+ but found v${node_version}"
  [[ -x "${NODE_INSTALL_ROOT}/current/bin/pnpm" ]] || die "managed pnpm binary is missing"
}

verify_dev_install() {
  local pkg
  local cmd
  for pkg in "${DEV_PACKAGES[@]}"; do
    package_is_installed "$pkg" || die "package '$pkg' is not installed"
  done
  for cmd in node npm npx corepack pnpm pnpx nmap strace lsof netstat ss jq yamllint valgrind perf pipx pkg-config htop; do
    command_is_available "$cmd" || die "command '$cmd' is not available"
  done
  verify_node_runtime
}

remove_managed_link() {
  local path="$1"
  if [[ -L "$path" ]] && [[ "$(readlink -f "$path")" == "${NODE_INSTALL_ROOT}"/* ]]; then
    run_cmd rm -f -- "$path"
  fi
}

remove_dev_install() {
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive apt remove "${apt_args[@]}" "${DEV_PACKAGES[@]}" || true
  remove_managed_link /usr/local/bin/node
  remove_managed_link /usr/local/bin/npm
  remove_managed_link /usr/local/bin/npx
  remove_managed_link /usr/local/bin/corepack
  remove_managed_link /usr/local/bin/pnpm
  remove_managed_link /usr/local/bin/pnpx
  run_cmd rm -rf -- "$NODE_INSTALL_ROOT"
}
