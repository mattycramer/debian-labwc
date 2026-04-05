#!/usr/bin/env bash

readonly BOOTSTRAP_PACKAGES=(
  ca-certificates
  curl
  gpg
  xz-utils
  autotools-dev
  netbase
  python3
  pkg-config
  build-essential
  autoconf
  automake
  libtool
  gettext
  bison
  flex
  nftables
)

readonly BOOTSTRAP_RUNTIME_PACKAGES=(
  libmnl0
  libnftnl11
  libjansson4
  libgmp10
  libreadline8t64
  libedit2
  libsystemd0
  libxtables12
  libacl1
  libattr1
  libaudit1
  libcap2
)

readonly BOOTSTRAP_DEV_PACKAGES=(
  libmnl-dev
  libnftnl-dev
  libjansson-dev
  libgmp-dev
  libreadline-dev
  libedit-dev
  libsystemd-dev
  libxtables-dev
  libacl1-dev
  libattr1-dev
  libaudit-dev
  libcap-dev
  nettle-dev
  zlib1g-dev
  libpcre2-dev
)

readonly CROWDSEC_PACKAGES=(
  crowdsec
  crowdsec-firewall-bouncer-nftables
)

readonly SECURITY_RUNTIME_ROOT="/var/lib/labwc-security"
readonly MANIFEST_ROOT="${SECURITY_RUNTIME_ROOT}/manifests"
readonly CROWDSEC_KEYRING_PATH="/etc/apt/keyrings/crowdsec_crowdsec-archive-keyring.gpg"
readonly CROWDSEC_SOURCE_PATH="/etc/apt/sources.list.d/crowdsec_crowdsec.sources"
readonly CROWDSEC_PREFS_PATH="/etc/apt/preferences.d/crowdsec"
readonly CROWDSEC_ACQUIS_PATH="/etc/crowdsec/acquis.d/labwc-security.yaml"
readonly CROWDSEC_BOUNCER_KEY_PATH="/etc/crowdsec/bouncers/labwc-firewall-bouncer.key"
readonly CROWDSEC_BOUNCER_CONFIG_PATH="/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml.local"
readonly CROWDSEC_CONSOLE_MARKER="/etc/crowdsec/.console-enrolled-by-labwc-security"
readonly NFT_BIN="/usr/local/sbin/nft"
readonly NFTABLES_CONF_PATH="/etc/nftables.conf"
readonly NFTABLES_DROPIN_DIR="/etc/systemd/system/nftables.service.d"
readonly NFTABLES_DROPIN_PATH="/etc/systemd/system/nftables.service.d/override.conf"
readonly NFTABLES_RULES_DIR="/etc/nftables.d"
readonly NFTABLES_BASE_RULES_PATH="/etc/nftables.d/10-base-filter.nft"
readonly NFTABLES_CROWDSEC_RULES_PATH="/etc/nftables.d/50-crowdsec.nft"
readonly CROWDSEC_BOUNCER_DROPIN_DIR="/etc/systemd/system/crowdsec-firewall-bouncer.service.d"
readonly CROWDSEC_BOUNCER_DROPIN_PATH="/etc/systemd/system/crowdsec-firewall-bouncer.service.d/override.conf"
readonly AIDE_CONF_DIR="/etc/aide"
readonly AIDE_CONF_PATH="/etc/aide/aide.conf"
readonly AIDE_DB_DIR="/var/lib/aide"
readonly AIDE_DB_PATH="/var/lib/aide/aide.db.gz"
readonly AIDE_DB_NEW_PATH="/var/lib/aide/aide.db.new.gz"
readonly AIDE_CHECK_SERVICE_PATH="/etc/systemd/system/labwc-security-aide-check.service"
readonly AIDE_CHECK_TIMER_PATH="/etc/systemd/system/labwc-security-aide-check.timer"
readonly SECURITY_VERSIONS_PATH="${SECURITY_RUNTIME_ROOT}/installed-versions.env"
readonly LDCONFIG_BIN="/usr/sbin/ldconfig"

detect_security_download_user() {
  if [[ -n "${SECURITY_DOWNLOAD_USER:-}" ]] && id "$SECURITY_DOWNLOAD_USER" >/dev/null 2>&1; then
    :
  elif [[ -n "${SUDO_USER:-}" ]] && [[ "${SUDO_USER:-}" != "root" ]] && id "${SUDO_USER:-}" >/dev/null 2>&1; then
    SECURITY_DOWNLOAD_USER="$SUDO_USER"
  elif getent passwd _apt >/dev/null 2>&1; then
    SECURITY_DOWNLOAD_USER="_apt"
  elif getent passwd nobody >/dev/null 2>&1; then
    SECURITY_DOWNLOAD_USER="nobody"
  else
    SECURITY_DOWNLOAD_USER="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /(false|nologin)$/ {print $1; exit}')"
  fi
  [[ -n "${SECURITY_DOWNLOAD_USER:-}" ]] || die "could not determine security download user"
  SECURITY_DOWNLOAD_GROUP="$(id -gn "$SECURITY_DOWNLOAD_USER")"
  SECURITY_DOWNLOAD_HOME="$(getent passwd "$SECURITY_DOWNLOAD_USER" | awk -F: '{print $6}')"
  [[ -n "${SECURITY_DOWNLOAD_HOME:-}" ]] || SECURITY_DOWNLOAD_HOME="/tmp"
}

ensure_crowdsec_console_enrollment_key() {
  if [[ -f "$CROWDSEC_CONSOLE_MARKER" ]]; then
    return 0
  fi
  if [[ -n "${CROWDSEC_CONSOLE_ENROLLMENT_KEY:-}" ]]; then
    return 0
  fi
  [[ -t 0 ]] || die "CROWDSEC_CONSOLE_ENROLLMENT_KEY is empty and no interactive terminal is available for prompting"
  IFS= read -r -s -p "No CrowdSec Enrollment Key Set. Enter Enrollment Key: " CROWDSEC_CONSOLE_ENROLLMENT_KEY
  printf '\n'
  [[ -n "${CROWDSEC_CONSOLE_ENROLLMENT_KEY:-}" ]] || die "no CrowdSec enrollment key was provided"
}

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
  retry_cmd 3 env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt update -o Acquire::Retries=3 -o Acquire::http::Timeout=20
}

apt_get_install_packages() {
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none \
    apt-get install --no-install-recommends "${apt_args[@]}" "$@"
}

prepare_security_download_path() {
  local path="$1"
  run_cmd runuser -u "$SECURITY_DOWNLOAD_USER" -- mkdir -p "$(dirname "$path")"
  run_cmd runuser -u "$SECURITY_DOWNLOAD_USER" -- rm -f -- "$path"
}

download_as_security_user() {
  local url="$1"
  local path="$2"
  prepare_security_download_path "$path"
  run_cmd runuser -u "$SECURITY_DOWNLOAD_USER" -- env HOME="$SECURITY_DOWNLOAD_HOME" TMPDIR=/tmp curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 300 --silent --show-error -o "$path" "$url"
  run_cmd chmod 0644 "$path"
}

fetch_as_security_user() {
  local url="$1"
  runuser -u "$SECURITY_DOWNLOAD_USER" -- env HOME="$SECURITY_DOWNLOAD_HOME" TMPDIR=/tmp curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 120 --silent --show-error "$url"
}

write_text_file() {
  local destination="$1"
  local content="$2"
  run_cmd install -D -m 0644 /dev/null "$destination"
  printf '%s' "$content" >"$destination"
}

install_bootstrap_packages() {
  apt_get_install_packages "${BOOTSTRAP_PACKAGES[@]}"
  apt_get_install_packages "${BOOTSTRAP_RUNTIME_PACKAGES[@]}"
  apt_get_install_packages "${BOOTSTRAP_DEV_PACKAGES[@]}"
}

install_crowdsec_repository() {
  local key_path="/tmp/crowdsec-packagecloud.key"
  run_cmd install -d -m 0755 /etc/apt/keyrings
  download_as_security_user "https://packagecloud.io/crowdsec/crowdsec/gpgkey" "$key_path"
  run_cmd gpg --dearmor --yes --output "$CROWDSEC_KEYRING_PATH" "$key_path"
  run_cmd rm -f -- "$key_path"
  run_cmd chmod 0644 "$CROWDSEC_KEYRING_PATH"
  write_text_file "$CROWDSEC_SOURCE_PATH" $'Types: deb deb-src\nURIs: https://packagecloud.io/crowdsec/crowdsec/any\nSuites: any\nComponents: main\nArchitectures: amd64\nSigned-By: /etc/apt/keyrings/crowdsec_crowdsec-archive-keyring.gpg\n'
  write_text_file "$CROWDSEC_PREFS_PATH" $'Package: *\nPin: release o=packagecloud.io/crowdsec/crowdsec,a=any,n=any,c=main\nPin-Priority: 1001\n'
}

install_crowdsec_packages() {
  apt_get_install_packages "${CROWDSEC_PACKAGES[@]}"
}

resolve_nftables_release() {
  local page
  page="$(fetch_as_security_user "https://www.nftables.org/projects/nftables/downloads.html")"
  NFTABLES_TARBALL="$(printf '%s' "$page" | grep -o 'nftables-[0-9][0-9.]*\.tar\.xz' | sort -Vu | tail -n1)"
  [[ -n "${NFTABLES_TARBALL:-}" ]] || die "could not resolve latest nftables release"
  NFTABLES_VERSION="${NFTABLES_TARBALL#nftables-}"
  NFTABLES_VERSION="${NFTABLES_VERSION%.tar.xz}"
  NFTABLES_URL="https://www.nftables.org/projects/nftables/files/${NFTABLES_TARBALL}"
  export NFTABLES_TARBALL NFTABLES_VERSION NFTABLES_URL
}

resolve_libmnl_release() {
  local page
  page="$(fetch_as_security_user "https://www.netfilter.org/projects/libmnl/downloads.html")"
  LIBMNL_TARBALL="$(printf '%s' "$page" | grep -o 'libmnl-[0-9][0-9.]*\.tar\.bz2' | sort -Vu | tail -n1)"
  [[ -n "${LIBMNL_TARBALL:-}" ]] || die "could not resolve latest libmnl release"
  LIBMNL_VERSION="${LIBMNL_TARBALL#libmnl-}"
  LIBMNL_VERSION="${LIBMNL_VERSION%.tar.bz2}"
  LIBMNL_URL="https://www.netfilter.org/projects/libmnl/files/${LIBMNL_TARBALL}"
  export LIBMNL_TARBALL LIBMNL_VERSION LIBMNL_URL
}

resolve_libnftnl_release() {
  local page
  page="$(fetch_as_security_user "https://www.netfilter.org/projects/libnftnl/downloads.html")"
  LIBNFTNL_TARBALL="$(printf '%s' "$page" | grep -o 'libnftnl-[0-9][0-9.]*\.tar\.xz' | sort -Vu | tail -n1)"
  [[ -n "${LIBNFTNL_TARBALL:-}" ]] || die "could not resolve latest libnftnl release"
  LIBNFTNL_VERSION="${LIBNFTNL_TARBALL#libnftnl-}"
  LIBNFTNL_VERSION="${LIBNFTNL_VERSION%.tar.xz}"
  LIBNFTNL_URL="https://www.netfilter.org/projects/libnftnl/files/${LIBNFTNL_TARBALL}"
  export LIBNFTNL_TARBALL LIBNFTNL_VERSION LIBNFTNL_URL
}

resolve_aide_release() {
  local json
  json="$(fetch_as_security_user "https://api.github.com/repos/aide/aide/releases/latest")"
  AIDE_TAG="$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')"
  [[ -n "${AIDE_TAG:-}" ]] || die "could not resolve latest AIDE release"
  AIDE_VERSION="${AIDE_TAG#v}"
  AIDE_TARBALL="aide-${AIDE_VERSION}.tar.gz"
  AIDE_URL="https://github.com/aide/aide/releases/download/${AIDE_TAG}/${AIDE_TARBALL}"
  export AIDE_TAG AIDE_VERSION AIDE_TARBALL AIDE_URL
}

resolve_crowdsec_release() {
  local json
  json="$(fetch_as_security_user "https://api.github.com/repos/crowdsecurity/crowdsec/releases/latest")"
  CROWDSEC_TAG="$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')"
  CROWDSEC_VERSION="${CROWDSEC_TAG#v}"
  export CROWDSEC_TAG CROWDSEC_VERSION
}

resolve_crowdsec_bouncer_release() {
  local json
  json="$(fetch_as_security_user "https://api.github.com/repos/crowdsecurity/cs-firewall-bouncer/releases/latest")"
  CROWDSEC_BOUNCER_TAG="$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')"
  CROWDSEC_BOUNCER_VERSION="${CROWDSEC_BOUNCER_TAG#v}"
  export CROWDSEC_BOUNCER_TAG CROWDSEC_BOUNCER_VERSION
}

remove_manifest_files() {
  local manifest_path="$1"
  [[ -f "$manifest_path" ]] || return 0
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    run_cmd rm -f -- "$path"
  done <"$manifest_path"
  run_cmd rm -f -- "$manifest_path"
}

copy_staged_tree() {
  local stage_root="$1"
  local manifest_name="$2"
  local manifest_path="${MANIFEST_ROOT}/${manifest_name}.files"

  run_cmd install -d -m 0755 "$MANIFEST_ROOT"
  remove_manifest_files "$manifest_path"

  : >"$manifest_path"
  while IFS= read -r -d '' staged_path; do
    local relative_path="${staged_path#$stage_root}"
    [[ -n "$relative_path" ]] || continue
    run_cmd install -d -m 0755 "$(dirname "$relative_path")"
    run_cmd cp -a "$staged_path" "$relative_path"
    printf '%s\n' "$relative_path" >>"$manifest_path"
  done < <(find "$stage_root" -mindepth 1 \( -type f -o -type l \) -print0 | sort -z)
}

netfilter_pkg_config_path() {
  printf '/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig%s' "${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
}

security_cc() {
  if [[ -n "${CC:-}" ]]; then
    printf '%s\n' "$CC"
    return 0
  fi
  command -v cc
}

security_cxx() {
  if [[ -n "${CXX:-}" ]]; then
    printf '%s\n' "$CXX"
    return 0
  fi
  command -v c++
}

security_compiler_id() {
  local compiler="$1"
  local resolved_compiler=""
  local version_output=""

  resolved_compiler="$(readlink -f "$compiler" 2>/dev/null || printf '%s' "$compiler")"
  version_output="$("$compiler" --version 2>/dev/null || true)"
  case "${resolved_compiler##*/}:${version_output,,}" in
    *clang*:*|*:*clang*)
      printf '%s\n' "clang"
      ;;
    *gcc*:*|*g++*:*|*:*gcc*|*:*gnu*)
      printf '%s\n' "gcc"
      ;;
    *) printf '%s\n' "unknown" ;;
  esac
}

security_native_lto_flag() {
  local compiler_id="$1"

  case "$compiler_id" in
    clang) printf '%s\n' "-flto=thin" ;;
    gcc) printf '%s\n' "-flto=auto" ;;
    *) printf '%s\n' "" ;;
  esac
}

security_native_cflags() {
  local compiler_id lto_flag flags

  compiler_id="$(security_compiler_id "$(security_cc)")"
  lto_flag="$(security_native_lto_flag "$compiler_id")"
  flags="-O3 -march=native -mtune=native -pipe -fno-plt -DNDEBUG"
  if [[ -n "$lto_flag" ]]; then
    flags+=" $lto_flag"
  fi
  printf '%s\n' "$flags"
}

security_native_cxxflags() {
  printf '%s\n' "$(security_native_cflags)"
}

security_native_ldflags() {
  local compiler_id lto_flag flags

  compiler_id="$(security_compiler_id "$(security_cc)")"
  lto_flag="$(security_native_lto_flag "$compiler_id")"
  flags="-Wl,-O2 -Wl,--as-needed"
  if [[ -n "$lto_flag" ]]; then
    flags="$lto_flag $flags"
  fi
  printf '%s\n' "$flags"
}

finalize_local_libtool_install() {
  run_cmd "$LDCONFIG_BIN"
}

install_latest_libmnl() {
  resolve_libmnl_release

  local tmpdir archive_path source_dir stage_root
  tmpdir="${SECURITY_RUNTIME_ROOT}/build-libmnl"
  run_cmd rm -rf -- "$tmpdir"
  run_cmd install -d -m 0755 "$tmpdir"
  archive_path="${tmpdir}/${LIBMNL_TARBALL}"
  source_dir="${tmpdir}/libmnl-${LIBMNL_VERSION}"
  stage_root="${tmpdir}/stage"

  run_cmd chown "$SECURITY_DOWNLOAD_USER:$SECURITY_DOWNLOAD_GROUP" "$tmpdir"
  download_as_security_user "$LIBMNL_URL" "$archive_path"
  run_cmd tar -xjf "$archive_path" -C "$tmpdir"
  (
    export CC CXX CFLAGS CXXFLAGS LDFLAGS
    CC="$(security_cc)"
    CXX="$(security_cxx)"
    CFLAGS="$(security_native_cflags)"
    CXXFLAGS="$(security_native_cxxflags)"
    LDFLAGS="$(security_native_ldflags)"
    cd "$source_dir" || exit 1
    run_cmd ./configure --prefix=/usr/local
    run_cmd make -j"$(nproc)"
    run_cmd make DESTDIR="$stage_root" install
  )
  copy_staged_tree "$stage_root" "libmnl"
  finalize_local_libtool_install
  run_cmd rm -rf -- "$tmpdir"
}

install_latest_libnftnl() {
  resolve_libnftnl_release

  local tmpdir archive_path source_dir stage_root
  tmpdir="${SECURITY_RUNTIME_ROOT}/build-libnftnl"
  run_cmd rm -rf -- "$tmpdir"
  run_cmd install -d -m 0755 "$tmpdir"
  archive_path="${tmpdir}/${LIBNFTNL_TARBALL}"
  source_dir="${tmpdir}/libnftnl-${LIBNFTNL_VERSION}"
  stage_root="${tmpdir}/stage"

  run_cmd chown "$SECURITY_DOWNLOAD_USER:$SECURITY_DOWNLOAD_GROUP" "$tmpdir"
  download_as_security_user "$LIBNFTNL_URL" "$archive_path"
  run_cmd tar -xJf "$archive_path" -C "$tmpdir"
  (
    export CC CXX PKG_CONFIG_PATH CFLAGS CXXFLAGS LDFLAGS
    CC="$(security_cc)"
    CXX="$(security_cxx)"
    PKG_CONFIG_PATH="$(netfilter_pkg_config_path)"
    CFLAGS="$(security_native_cflags)"
    CXXFLAGS="$(security_native_cxxflags)"
    LDFLAGS="$(security_native_ldflags)"
    cd "$source_dir" || exit 1
    run_cmd ./configure --prefix=/usr/local
    run_cmd make -j"$(nproc)"
    run_cmd make DESTDIR="$stage_root" install
  )
  copy_staged_tree "$stage_root" "libnftnl"
  finalize_local_libtool_install
  run_cmd rm -rf -- "$tmpdir"
}

install_latest_nftables() {
  install_latest_libmnl
  install_latest_libnftnl
  resolve_nftables_release

  local tmpdir archive_path source_dir stage_root
  tmpdir="${SECURITY_RUNTIME_ROOT}/build-nftables"
  run_cmd rm -rf -- "$tmpdir"
  run_cmd install -d -m 0755 "$tmpdir"
  archive_path="${tmpdir}/${NFTABLES_TARBALL}"
  source_dir="${tmpdir}/nftables-${NFTABLES_VERSION}"
  stage_root="${tmpdir}/stage"

  run_cmd chown "$SECURITY_DOWNLOAD_USER:$SECURITY_DOWNLOAD_GROUP" "$tmpdir"
  download_as_security_user "$NFTABLES_URL" "$archive_path"
  run_cmd tar -xJf "$archive_path" -C "$tmpdir"
  (
    export CC CXX PKG_CONFIG_PATH CFLAGS CXXFLAGS LDFLAGS
    CC="$(security_cc)"
    CXX="$(security_cxx)"
    PKG_CONFIG_PATH="$(netfilter_pkg_config_path)"
    CFLAGS="$(security_native_cflags)"
    CXXFLAGS="$(security_native_cxxflags)"
    LDFLAGS="$(security_native_ldflags)"
    cd "$source_dir" || exit 1
    run_cmd ./configure --prefix=/usr/local
    run_cmd make -j"$(nproc)"
    run_cmd make DESTDIR="$stage_root" install
  )
  copy_staged_tree "$stage_root" "nftables"
  finalize_local_libtool_install
  run_cmd rm -rf -- "$tmpdir"
}

install_latest_aide() {
  resolve_aide_release

  local tmpdir archive_path source_dir stage_root
  tmpdir="${SECURITY_RUNTIME_ROOT}/build-aide"
  run_cmd rm -rf -- "$tmpdir"
  run_cmd install -d -m 0755 "$tmpdir"
  archive_path="${tmpdir}/${AIDE_TARBALL}"
  source_dir="${tmpdir}/aide-${AIDE_VERSION}"
  stage_root="${tmpdir}/stage"

  run_cmd chown "$SECURITY_DOWNLOAD_USER:$SECURITY_DOWNLOAD_GROUP" "$tmpdir"
  download_as_security_user "$AIDE_URL" "$archive_path"
  run_cmd tar -xzf "$archive_path" -C "$tmpdir"
  (
    export CC CXX CFLAGS CXXFLAGS LDFLAGS
    CC="$(security_cc)"
    CXX="$(security_cxx)"
    CFLAGS="$(security_native_cflags)"
    CXXFLAGS="$(security_native_cxxflags)"
    LDFLAGS="$(security_native_ldflags)"
    cd "$source_dir" || exit 1
    run_cmd ./configure --prefix=/usr/local --without-selinux
    run_cmd make -j"$(nproc)"
    run_cmd make DESTDIR="$stage_root" install
  )
  copy_staged_tree "$stage_root" "aide"
  run_cmd "$LDCONFIG_BIN"
  run_cmd rm -rf -- "$tmpdir"
}

render_crowdsec_acquis() {
  local -a log_files=()
  local candidate
  for candidate in /var/log/auth.log /var/log/syslog /var/log/kern.log; do
    [[ -e "$candidate" ]] && log_files+=("$candidate")
  done
  if [[ "${#log_files[@]}" -eq 0 ]]; then
    log_files=(/var/log/auth.log)
  fi

  local content='filenames:
'
  for candidate in "${log_files[@]}"; do
    content+="  - ${candidate}"$'\n'
  done
  content+=$'labels:\n  type: syslog\n'
  write_text_file "$CROWDSEC_ACQUIS_PATH" "$content"
}

generate_bouncer_api_key() {
  openssl rand -hex 24
}

ensure_crowdsec_bouncer_key() {
  local api_key
  if [[ -s "$CROWDSEC_BOUNCER_KEY_PATH" ]]; then
    CROWDSEC_BOUNCER_API_KEY="$(tr -d '\n' <"$CROWDSEC_BOUNCER_KEY_PATH")"
  else
    api_key="$(generate_bouncer_api_key)"
    if ! run_cmd cscli bouncers add "$CROWDSEC_BOUNCER_NAME" --key "$api_key"; then
      run_cmd cscli bouncers delete "$CROWDSEC_BOUNCER_NAME" || true
      run_cmd cscli bouncers add "$CROWDSEC_BOUNCER_NAME" --key "$api_key"
    fi
    printf '%s\n' "$api_key" >"$CROWDSEC_BOUNCER_KEY_PATH"
    chmod 0600 "$CROWDSEC_BOUNCER_KEY_PATH"
    CROWDSEC_BOUNCER_API_KEY="$api_key"
  fi
  export CROWDSEC_BOUNCER_API_KEY
}

wait_for_crowdsec_lapi() {
  local attempt=1
  while (( attempt <= 30 )); do
    if cscli lapi status >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    attempt=$((attempt + 1))
  done
  die "crowdsec local API did not become ready"
}

render_all_configs() {
  run_cmd install -d -m 0755 "$NFTABLES_RULES_DIR" "$NFTABLES_DROPIN_DIR" "$CROWDSEC_BOUNCER_DROPIN_DIR" /etc/crowdsec/acquis.d /etc/crowdsec/bouncers "$AIDE_CONF_DIR" "$AIDE_DB_DIR"

  write_text_file "$NFTABLES_CONF_PATH" $'flush ruleset\ninclude "/etc/nftables.d/*.nft"\n'

  write_text_file "$NFTABLES_BASE_RULES_PATH" $'table inet base-filter {\n  chain input {\n    type filter hook input priority filter + 10; policy drop;\n\n    iifname "lo" accept\n    ct state { established, related } accept\n    ct state invalid drop\n\n    icmp type { destination-unreachable, time-exceeded, parameter-problem, echo-request } accept\n    icmpv6 type { destination-unreachable, packet-too-big, time-exceeded, parameter-problem, nd-neighbor-solicit, nd-neighbor-advert, nd-router-advert, nd-redirect, echo-request } accept\n\n    udp sport 67 udp dport 68 accept\n    udp sport 547 udp dport 546 accept\n  }\n\n  chain forward {\n    type filter hook forward priority filter + 10; policy drop;\n  }\n\n  chain output {\n    type filter hook output priority filter + 10; policy accept;\n  }\n}\n'
  write_text_file "$NFTABLES_CROWDSEC_RULES_PATH" $'table ip crowdsec {\n  set crowdsec-blacklists {\n    type ipv4_addr\n    flags timeout\n  }\n\n  chain crowdsec-chain-input {\n    type filter hook input priority filter - 10; policy accept;\n    ip saddr @crowdsec-blacklists drop\n  }\n}\n\ntable ip6 crowdsec6 {\n  set crowdsec6-blacklists {\n    type ipv6_addr\n    flags timeout\n  }\n\n  chain crowdsec6-chain-input {\n    type filter hook input priority filter - 10; policy accept;\n    ip6 saddr @crowdsec6-blacklists drop\n  }\n}\n'

  write_text_file "$NFTABLES_DROPIN_PATH" $'[Unit]\nWants=local-fs.target\nAfter=local-fs.target\n\n[Service]\nExecStart=\nExecStart=/usr/local/sbin/nft -f /etc/nftables.conf\nExecReload=\nExecReload=/usr/local/sbin/nft -f /etc/nftables.conf\nExecStop=\nExecStop=/usr/local/sbin/nft flush ruleset\n'
  write_text_file "$CROWDSEC_BOUNCER_DROPIN_PATH" $'[Unit]\nWants=nftables.service crowdsec.service\nAfter=nftables.service crowdsec.service\n\n[Service]\nRestart=on-failure\nRestartSec=5s\n'

  render_crowdsec_acquis

  write_text_file "$AIDE_CONF_PATH" $'database_in=file:/var/lib/aide/aide.db.gz\ndatabase_out=file:/var/lib/aide/aide.db.new.gz\ngzip_dbout=yes\nreport_summarize_changes=yes\nreport_grouped=yes\nwarn_dead_symlinks=yes\n\nNORMAL = ftype+p+u+g+n+s+m+c+acl+xattrs+sha256\nDIR = ftype+p+u+g+n+acl+xattrs\n\n-/dev\n-/proc\n-/run\n-/sys\n-/tmp\n-/var/tmp\n-/var/cache\n-/var/spool\n-/var/log\n-/var/log/journal\n-/var/swap\n-/pool\n-/data/workspace\n-/data/codex\n-/media\n-/mnt\n-/lost\\+found\n-/var/lib/aide\n-/var/lib/crowdsec\n-/var/lib/containerd\n-/var/lib/docker\n-/var/lib/containers\n-/var/lib/systemd/coredump\n\n/etc$ DIR\n/etc/ NORMAL\n/usr$ DIR\n/usr/ NORMAL\n/usr/local$ DIR\n/usr/local/ NORMAL\n/boot$ DIR\n/boot/ NORMAL\n/opt$ DIR\n/opt/ NORMAL\n/root$ DIR\n/root/ NORMAL\n/var/lib/systemd$ DIR\n/var/lib/systemd/ NORMAL\n/var/lib/dpkg$ DIR\n/var/lib/dpkg/ NORMAL\n'

  write_text_file "$AIDE_CHECK_SERVICE_PATH" $'[Unit]\nDescription=Labwc security AIDE integrity check\nWants=network-online.target\nAfter=network-online.target\n\n[Service]\nType=oneshot\nExecStart=/usr/local/bin/aide --config=/etc/aide/aide.conf --check\nNice=19\nIOSchedulingClass=best-effort\nIOSchedulingPriority=7\n'

  write_text_file "$AIDE_CHECK_TIMER_PATH" "[Unit]
Description=Labwc security AIDE scheduled integrity check

[Timer]
OnCalendar=${AIDE_CHECK_ONCALENDAR}
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
"
}

systemd_daemon_reload() {
  run_cmd systemctl daemon-reload
}

validate_nftables_config() {
  run_cmd "$NFT_BIN" -c -f "$NFTABLES_CONF_PATH"
}

initialize_nftables() {
  validate_nftables_config
  run_cmd systemctl enable --now nftables.service
}

initialize_crowdsec() {
  run_cmd systemctl enable --now crowdsec.service
  wait_for_crowdsec_lapi
  run_cmd cscli collections install crowdsecurity/linux crowdsecurity/sshd
  ensure_crowdsec_bouncer_key
  write_text_file "$CROWDSEC_BOUNCER_CONFIG_PATH" "mode: nftables
api_url: http://127.0.0.1:8080/
api_key: ${CROWDSEC_BOUNCER_API_KEY}
update_frequency: 10s
deny_action: DROP
nftables:
  ipv4:
    enabled: true
    set-only: true
    table: crowdsec
    chain: crowdsec-chain-input
  ipv6:
    enabled: true
    set-only: true
    table: crowdsec6
    chain: crowdsec6-chain-input
"

  if [[ -n "${CROWDSEC_CONSOLE_ENROLLMENT_KEY:-}" && ! -f "$CROWDSEC_CONSOLE_MARKER" ]]; then
    if run_cmd cscli console enroll "$CROWDSEC_CONSOLE_ENROLLMENT_KEY"; then
      run_cmd touch "$CROWDSEC_CONSOLE_MARKER"
    else
      log_warn "CrowdSec console enrollment was not completed; leaving instance unenrolled"
    fi
  fi
}

initialize_aide_database() {
  run_cmd install -d -m 0700 "$AIDE_DB_DIR"
  if [[ -f "$AIDE_DB_PATH" ]]; then
    return 0
  fi
  run_cmd /usr/local/bin/aide --config="$AIDE_CONF_PATH" --init
  run_cmd mv -- "$AIDE_DB_NEW_PATH" "$AIDE_DB_PATH"
  run_cmd chmod 0600 "$AIDE_DB_PATH"
}

record_installed_security_versions() {
  local installed_nft_version installed_aide_version installed_crowdsec_version installed_bouncer_version
  local content
  installed_nft_version="$("$NFT_BIN" --version 2>/dev/null | grep -o '[0-9][0-9.]*' | head -n1)"
  [[ -n "$installed_nft_version" ]] || die "could not determine installed nftables version"
  installed_aide_version="$(/usr/local/bin/aide --version 2>/dev/null | grep -o '[0-9][0-9.]*' | head -n1)"
  [[ -n "$installed_aide_version" ]] || die "could not determine installed AIDE version"
  installed_crowdsec_version="$(crowdsec -version 2>/dev/null | grep -o '[0-9][0-9.]*' | head -n1)"
  [[ -n "$installed_crowdsec_version" ]] || die "could not determine installed CrowdSec version"
  installed_bouncer_version="$(crowdsec-firewall-bouncer -version 2>/dev/null | grep -o '[0-9][0-9.]*' | head -n1)"
  [[ -n "$installed_bouncer_version" ]] || die "could not determine installed firewall bouncer version"
  content="$(cat <<EOF
NFTABLES_VERSION="${installed_nft_version}"
AIDE_VERSION="${installed_aide_version}"
CROWDSEC_VERSION="${installed_crowdsec_version}"
CROWDSEC_BOUNCER_VERSION="${installed_bouncer_version}"
EOF
)"
  write_text_file "$SECURITY_VERSIONS_PATH" "$content"
}

enable_security_services() {
  run_cmd systemctl enable --now crowdsec-firewall-bouncer.service
  run_cmd systemctl enable --now labwc-security-aide-check.timer
}

command_is_available() {
  command -v "$1" >/dev/null 2>&1
}

verify_path_exists() {
  [[ -e "$1" ]] || die "missing path: $1"
}

verify_security_install() {
  local installed_nft_version installed_aide_version installed_crowdsec_version installed_bouncer_version

  verify_path_exists "$CROWDSEC_KEYRING_PATH"
  verify_path_exists "$CROWDSEC_SOURCE_PATH"
  verify_path_exists "$CROWDSEC_PREFS_PATH"
  verify_path_exists "$NFTABLES_CONF_PATH"
  verify_path_exists "$NFTABLES_BASE_RULES_PATH"
  verify_path_exists "$NFTABLES_CROWDSEC_RULES_PATH"
  verify_path_exists "$NFTABLES_DROPIN_PATH"
  verify_path_exists "$CROWDSEC_ACQUIS_PATH"
  verify_path_exists "$CROWDSEC_BOUNCER_CONFIG_PATH"
  verify_path_exists "$CROWDSEC_BOUNCER_DROPIN_PATH"
  verify_path_exists "$AIDE_CONF_PATH"
  verify_path_exists "$AIDE_DB_PATH"
  verify_path_exists "$AIDE_CHECK_SERVICE_PATH"
  verify_path_exists "$AIDE_CHECK_TIMER_PATH"
  verify_path_exists "$SECURITY_VERSIONS_PATH"
  verify_path_exists "${MANIFEST_ROOT}/nftables.files"
  verify_path_exists "${MANIFEST_ROOT}/aide.files"
  verify_path_exists "${MANIFEST_ROOT}/libmnl.files"
  verify_path_exists "${MANIFEST_ROOT}/libnftnl.files"

  for cmd in "$NFT_BIN" /usr/local/bin/aide crowdsec cscli crowdsec-firewall-bouncer; do
    command_is_available "$cmd" || die "missing command: $cmd"
  done

  # shellcheck disable=SC1090
  source "$SECURITY_VERSIONS_PATH"
  installed_nft_version="$("$NFT_BIN" --version 2>/dev/null | grep -o '[0-9][0-9.]*' | head -n1)"
  [[ "$installed_nft_version" == "$NFTABLES_VERSION" ]] || die "expected nftables ${NFTABLES_VERSION}, found ${installed_nft_version:-unknown}"

  installed_aide_version="$(/usr/local/bin/aide --version 2>/dev/null | grep -o '[0-9][0-9.]*' | head -n1)"
  [[ "$installed_aide_version" == "$AIDE_VERSION" ]] || die "expected AIDE ${AIDE_VERSION}, found ${installed_aide_version:-unknown}"

  installed_crowdsec_version="$(crowdsec -version 2>/dev/null | grep -o '[0-9][0-9.]*' | head -n1)"
  [[ "$installed_crowdsec_version" == "$CROWDSEC_VERSION" ]] || die "expected CrowdSec ${CROWDSEC_VERSION}, found ${installed_crowdsec_version:-unknown}"

  installed_bouncer_version="$(crowdsec-firewall-bouncer -version 2>/dev/null | grep -o '[0-9][0-9.]*' | head -n1)"
  [[ "$installed_bouncer_version" == "$CROWDSEC_BOUNCER_VERSION" ]] || die "expected firewall bouncer ${CROWDSEC_BOUNCER_VERSION}, found ${installed_bouncer_version:-unknown}"

  grep -F 'policy drop' "$NFTABLES_BASE_RULES_PATH" >/dev/null || die "nftables base rules missing default drop policy"
  grep -F 'chain output' "$NFTABLES_BASE_RULES_PATH" >/dev/null || die "nftables base rules missing output chain"
  grep -F 'policy accept' "$NFTABLES_BASE_RULES_PATH" >/dev/null || die "nftables base rules missing accept policy for output traffic"
  grep -F 'udp sport 67 udp dport 68 accept' "$NFTABLES_BASE_RULES_PATH" >/dev/null || die "nftables base rules missing DHCPv4 client allowance"
  grep -F 'udp sport 547 udp dport 546 accept' "$NFTABLES_BASE_RULES_PATH" >/dev/null || die "nftables base rules missing DHCPv6 client allowance"
  grep -F 'set-only: true' "$CROWDSEC_BOUNCER_CONFIG_PATH" >/dev/null || die "bouncer config missing nftables set-only mode"
  grep -F 'api_url: http://127.0.0.1:8080/' "$CROWDSEC_BOUNCER_CONFIG_PATH" >/dev/null || die "bouncer config missing expected api url"
  grep -F 'chain: crowdsec-chain-input' "$CROWDSEC_BOUNCER_CONFIG_PATH" >/dev/null || die "bouncer config missing expected ipv4 chain"
  grep -F 'chain: crowdsec6-chain-input' "$CROWDSEC_BOUNCER_CONFIG_PATH" >/dev/null || die "bouncer config missing expected ipv6 chain"
  grep -F 'chain crowdsec-chain-input' "$NFTABLES_CROWDSEC_RULES_PATH" >/dev/null || die "nftables rules missing metrics-safe ipv4 chain name"
  grep -F 'chain crowdsec6-chain-input' "$NFTABLES_CROWDSEC_RULES_PATH" >/dev/null || die "nftables rules missing metrics-safe ipv6 chain name"
  grep -F 'After=nftables.service crowdsec.service' "$CROWDSEC_BOUNCER_DROPIN_PATH" >/dev/null || die "bouncer override missing nftables/crowdsec ordering"
  grep -F 'After=local-fs.target' "$NFTABLES_DROPIN_PATH" >/dev/null || die "nftables override missing local-fs ordering"
  grep -F '/data/workspace' "$AIDE_CONF_PATH" >/dev/null || die "AIDE config missing /data/workspace exclusion"
  grep -F '/var/log' "$AIDE_CONF_PATH" >/dev/null || die "AIDE config missing /var/log exclusion"
  grep -F '/tmp' "$AIDE_CONF_PATH" >/dev/null || die "AIDE config missing /tmp exclusion"

  validate_nftables_config
  systemctl is-active nftables.service >/dev/null 2>&1 || die "nftables.service is not active"
  systemctl is-active crowdsec.service >/dev/null 2>&1 || die "crowdsec.service is not active"
  systemctl is-active crowdsec-firewall-bouncer.service >/dev/null 2>&1 || die "crowdsec-firewall-bouncer.service is not active"
  systemctl is-active labwc-security-aide-check.timer >/dev/null 2>&1 || die "labwc-security-aide-check.timer is not active"
  systemctl is-enabled nftables.service >/dev/null 2>&1 || die "nftables.service is not enabled"
  systemctl is-enabled crowdsec.service >/dev/null 2>&1 || die "crowdsec.service is not enabled"
  systemctl is-enabled crowdsec-firewall-bouncer.service >/dev/null 2>&1 || die "crowdsec-firewall-bouncer.service is not enabled"
  systemctl is-enabled labwc-security-aide-check.timer >/dev/null 2>&1 || die "labwc-security-aide-check.timer is not enabled"
}

remove_security_install() {
  run_cmd systemctl disable --now labwc-security-aide-check.timer >/dev/null 2>&1 || true
  run_cmd systemctl disable --now crowdsec-firewall-bouncer.service >/dev/null 2>&1 || true
  run_cmd systemctl disable --now crowdsec.service >/dev/null 2>&1 || true
  run_cmd systemctl disable --now nftables.service >/dev/null 2>&1 || true

  remove_manifest_files "${MANIFEST_ROOT}/aide.files"
  remove_manifest_files "${MANIFEST_ROOT}/nftables.files"
  remove_manifest_files "${MANIFEST_ROOT}/libmnl.files"
  remove_manifest_files "${MANIFEST_ROOT}/libnftnl.files"
  run_cmd rm -rf -- "$MANIFEST_ROOT"

  run_cmd rm -f -- "$CROWDSEC_KEYRING_PATH" "$CROWDSEC_SOURCE_PATH" "$CROWDSEC_PREFS_PATH"
  run_cmd rm -f -- "$NFTABLES_CONF_PATH" "$NFTABLES_BASE_RULES_PATH" "$NFTABLES_CROWDSEC_RULES_PATH" "$NFTABLES_DROPIN_PATH" "$CROWDSEC_BOUNCER_DROPIN_PATH"
  run_cmd rmdir --ignore-fail-on-non-empty "$CROWDSEC_BOUNCER_DROPIN_DIR" >/dev/null 2>&1 || true
  run_cmd rmdir --ignore-fail-on-non-empty "$NFTABLES_DROPIN_DIR" >/dev/null 2>&1 || true
  run_cmd rmdir --ignore-fail-on-non-empty "$NFTABLES_RULES_DIR" >/dev/null 2>&1 || true
  run_cmd rm -f -- "$CROWDSEC_ACQUIS_PATH" "$CROWDSEC_BOUNCER_CONFIG_PATH" "$CROWDSEC_BOUNCER_KEY_PATH" "$CROWDSEC_CONSOLE_MARKER"
  run_cmd rm -f -- "$AIDE_CONF_PATH" "$AIDE_CHECK_SERVICE_PATH" "$AIDE_CHECK_TIMER_PATH" "$AIDE_DB_PATH" "$AIDE_DB_NEW_PATH" "$SECURITY_VERSIONS_PATH"
  run_cmd rmdir --ignore-fail-on-non-empty "$AIDE_CONF_DIR" >/dev/null 2>&1 || true
  run_cmd rmdir --ignore-fail-on-non-empty "$AIDE_DB_DIR" >/dev/null 2>&1 || true

  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt remove "${apt_args[@]}" crowdsec crowdsec-firewall-bouncer-nftables nftables || true
  run_cmd "$LDCONFIG_BIN"
  systemd_daemon_reload
}
