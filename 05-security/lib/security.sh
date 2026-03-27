#!/usr/bin/env bash

readonly BOOTSTRAP_PACKAGES=(
  ca-certificates
  curl
  gpg
  xz-utils
  build-essential
  autoconf
  automake
  libtool
  gettext
  bison
  flex
  pkg-config
  python3
  libmnl-dev
  libnftnl-dev
  libjansson-dev
  libgmp-dev
  libreadline-dev
  libedit-dev
  libacl1-dev
  libattr1-dev
  libselinux1-dev
  libaudit-dev
  libcap-dev
  zlib1g-dev
  libpcre2-dev
  nftables
  netbase
)

readonly CROWDSEC_PACKAGES=(
  crowdsec
  crowdsec-firewall-bouncer-nftables
)

readonly MANIFEST_ROOT="/var/lib/05-security/manifests"
readonly CROWDSEC_KEYRING_PATH="/etc/apt/keyrings/crowdsec_crowdsec-archive-keyring.gpg"
readonly CROWDSEC_LIST_PATH="/etc/apt/sources.list.d/crowdsec_crowdsec.list"
readonly CROWDSEC_PREFS_PATH="/etc/apt/preferences.d/crowdsec"
readonly CROWDSEC_ACQUIS_PATH="/etc/crowdsec/acquis.d/05-security.yaml"
readonly CROWDSEC_BOUNCER_KEY_PATH="/etc/crowdsec/bouncers/05-security-firewall-bouncer.key"
readonly CROWDSEC_BOUNCER_LOCAL_PATH="/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml.local"
readonly CROWDSEC_CONSOLE_MARKER="/etc/crowdsec/.console-enrolled-by-05-security"
readonly NFTABLES_CONF_PATH="/etc/nftables.conf"
readonly NFTABLES_DROPIN_DIR="/etc/systemd/system/nftables.service.d"
readonly NFTABLES_DROPIN_PATH="/etc/systemd/system/nftables.service.d/override.conf"
readonly NFTABLES_RULES_DIR="/etc/nftables.d"
readonly NFTABLES_CROWDSEC_RULES_PATH="/etc/nftables.d/50-crowdsec.nft"
readonly AIDE_CONF_DIR="/etc/aide"
readonly AIDE_CONF_PATH="/etc/aide/aide.conf"
readonly AIDE_DB_DIR="/var/lib/aide"
readonly AIDE_DB_PATH="/var/lib/aide/aide.db.gz"
readonly AIDE_DB_NEW_PATH="/var/lib/aide/aide.db.new.gz"
readonly AIDE_CHECK_SERVICE_PATH="/etc/systemd/system/05-security-aide-check.service"
readonly AIDE_CHECK_TIMER_PATH="/etc/systemd/system/05-security-aide-check.timer"

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

write_text_file() {
  local destination="$1"
  local content="$2"
  local temp_file
  temp_file="$(mktemp)"
  printf '%s' "$content" >"$temp_file"
  run_cmd install -D -m 0644 "$temp_file" "$destination"
  rm -f -- "$temp_file"
}

install_bootstrap_packages() {
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive apt install --no-install-recommends "${apt_args[@]}" "${BOOTSTRAP_PACKAGES[@]}"
}

install_crowdsec_repository() {
  run_cmd install -d -m 0755 /etc/apt/keyrings
  run_cmd bash -lc 'curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 120 --silent --show-error https://packagecloud.io/crowdsec/crowdsec/gpgkey | gpg --dearmor > /etc/apt/keyrings/crowdsec_crowdsec-archive-keyring.gpg'
  run_cmd chmod 0644 "$CROWDSEC_KEYRING_PATH"
  write_text_file "$CROWDSEC_LIST_PATH" $'deb [signed-by=/etc/apt/keyrings/crowdsec_crowdsec-archive-keyring.gpg] https://packagecloud.io/crowdsec/crowdsec/any any main\ndeb-src [signed-by=/etc/apt/keyrings/crowdsec_crowdsec-archive-keyring.gpg] https://packagecloud.io/crowdsec/crowdsec/any any main\n'
  write_text_file "$CROWDSEC_PREFS_PATH" $'Package: *\nPin: release o=packagecloud.io/crowdsec/crowdsec,a=any,n=any,c=main\nPin-Priority: 1001\n'
}

install_crowdsec_packages() {
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive apt install --no-install-recommends "${apt_args[@]}" "${CROWDSEC_PACKAGES[@]}"
}

resolve_nftables_release() {
  local page
  page="$(curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 120 --silent --show-error https://www.nftables.org/projects/nftables/downloads.html)"
  NFTABLES_TARBALL="$(printf '%s' "$page" | grep -o 'nftables-[0-9][0-9.]*\.tar\.xz' | head -n1)"
  [[ -n "${NFTABLES_TARBALL:-}" ]] || die "could not resolve latest nftables release"
  NFTABLES_VERSION="${NFTABLES_TARBALL#nftables-}"
  NFTABLES_VERSION="${NFTABLES_VERSION%.tar.xz}"
  NFTABLES_URL="https://www.nftables.org/projects/nftables/files/${NFTABLES_TARBALL}"
  export NFTABLES_TARBALL NFTABLES_VERSION NFTABLES_URL
}

resolve_libmnl_release() {
  local page
  page="$(curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 120 --silent --show-error https://www.netfilter.org/projects/libmnl/downloads.html)"
  LIBMNL_TARBALL="$(printf '%s' "$page" | grep -o 'libmnl-[0-9][0-9.]*\.tar\.bz2' | head -n1)"
  [[ -n "${LIBMNL_TARBALL:-}" ]] || die "could not resolve latest libmnl release"
  LIBMNL_VERSION="${LIBMNL_TARBALL#libmnl-}"
  LIBMNL_VERSION="${LIBMNL_VERSION%.tar.bz2}"
  LIBMNL_URL="https://www.netfilter.org/projects/libmnl/files/${LIBMNL_TARBALL}"
  export LIBMNL_TARBALL LIBMNL_VERSION LIBMNL_URL
}

resolve_libnftnl_release() {
  local page
  page="$(curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 120 --silent --show-error https://www.netfilter.org/projects/libnftnl/downloads.html)"
  LIBNFTNL_TARBALL="$(printf '%s' "$page" | grep -o 'libnftnl-[0-9][0-9.]*\.tar\.xz' | head -n1)"
  [[ -n "${LIBNFTNL_TARBALL:-}" ]] || die "could not resolve latest libnftnl release"
  LIBNFTNL_VERSION="${LIBNFTNL_TARBALL#libnftnl-}"
  LIBNFTNL_VERSION="${LIBNFTNL_VERSION%.tar.xz}"
  LIBNFTNL_URL="https://www.netfilter.org/projects/libnftnl/files/${LIBNFTNL_TARBALL}"
  export LIBNFTNL_TARBALL LIBNFTNL_VERSION LIBNFTNL_URL
}

resolve_aide_release() {
  local json
  json="$(curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 120 --silent --show-error https://api.github.com/repos/aide/aide/releases/latest)"
  AIDE_TAG="$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')"
  [[ -n "${AIDE_TAG:-}" ]] || die "could not resolve latest AIDE release"
  AIDE_VERSION="${AIDE_TAG#v}"
  AIDE_TARBALL="aide-${AIDE_VERSION}.tar.gz"
  AIDE_URL="https://github.com/aide/aide/releases/download/${AIDE_TAG}/${AIDE_TARBALL}"
  export AIDE_TAG AIDE_VERSION AIDE_TARBALL AIDE_URL
}

resolve_crowdsec_release() {
  local json
  json="$(curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 120 --silent --show-error https://api.github.com/repos/crowdsecurity/crowdsec/releases/latest)"
  CROWDSEC_TAG="$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')"
  CROWDSEC_VERSION="${CROWDSEC_TAG#v}"
  export CROWDSEC_TAG CROWDSEC_VERSION
}

resolve_crowdsec_bouncer_release() {
  local json
  json="$(curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 120 --silent --show-error https://api.github.com/repos/crowdsecurity/cs-firewall-bouncer/releases/latest)"
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

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    run_cmd bash -lc "cp -a '$stage_root'/. /"
    return 0
  fi

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

install_latest_libmnl() {
  resolve_libmnl_release

  local tmpdir archive_path source_dir stage_root
  tmpdir="$(mktemp -d)"
  archive_path="${tmpdir}/${LIBMNL_TARBALL}"
  source_dir="${tmpdir}/libmnl-${LIBMNL_VERSION}"
  stage_root="${tmpdir}/stage"

  run_cmd curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 300 --silent --show-error -o "$archive_path" "$LIBMNL_URL"
  run_cmd tar -xjf "$archive_path" -C "$tmpdir"
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    run_cmd bash -lc "cd '$source_dir' && ./configure --prefix=/usr/local"
    run_cmd bash -lc "cd '$source_dir' && make -j$(nproc)"
    run_cmd bash -lc "cd '$source_dir' && make DESTDIR='$stage_root' install"
  else
    (
      cd "$source_dir"
      run_cmd ./configure --prefix=/usr/local
      run_cmd make -j"$(nproc)"
      run_cmd make DESTDIR="$stage_root" install
    )
  fi
  copy_staged_tree "$stage_root" "libmnl"
  run_cmd ldconfig
  run_cmd rm -rf -- "$tmpdir"
}

install_latest_libnftnl() {
  resolve_libnftnl_release

  local tmpdir archive_path source_dir stage_root
  tmpdir="$(mktemp -d)"
  archive_path="${tmpdir}/${LIBNFTNL_TARBALL}"
  source_dir="${tmpdir}/libnftnl-${LIBNFTNL_VERSION}"
  stage_root="${tmpdir}/stage"

  run_cmd curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 300 --silent --show-error -o "$archive_path" "$LIBNFTNL_URL"
  run_cmd tar -xJf "$archive_path" -C "$tmpdir"
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    run_cmd bash -lc "cd '$source_dir' && export PKG_CONFIG_PATH='$(netfilter_pkg_config_path)' && ./configure --prefix=/usr/local"
    run_cmd bash -lc "cd '$source_dir' && export PKG_CONFIG_PATH='$(netfilter_pkg_config_path)' && make -j$(nproc)"
    run_cmd bash -lc "cd '$source_dir' && export PKG_CONFIG_PATH='$(netfilter_pkg_config_path)' && make DESTDIR='$stage_root' install"
  else
    (
      export PKG_CONFIG_PATH
      PKG_CONFIG_PATH="$(netfilter_pkg_config_path)"
      cd "$source_dir"
      run_cmd ./configure --prefix=/usr/local
      run_cmd make -j"$(nproc)"
      run_cmd make DESTDIR="$stage_root" install
    )
  fi
  copy_staged_tree "$stage_root" "libnftnl"
  run_cmd ldconfig
  run_cmd rm -rf -- "$tmpdir"
}

install_latest_nftables() {
  install_latest_libmnl
  install_latest_libnftnl
  resolve_nftables_release

  local tmpdir archive_path source_dir stage_root
  tmpdir="$(mktemp -d)"
  archive_path="${tmpdir}/${NFTABLES_TARBALL}"
  source_dir="${tmpdir}/nftables-${NFTABLES_VERSION}"
  stage_root="${tmpdir}/stage"

  run_cmd curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 300 --silent --show-error -o "$archive_path" "$NFTABLES_URL"
  run_cmd tar -xJf "$archive_path" -C "$tmpdir"
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    run_cmd bash -lc "cd '$source_dir' && export PKG_CONFIG_PATH='$(netfilter_pkg_config_path)' && ./configure --prefix=/usr/local"
    run_cmd bash -lc "cd '$source_dir' && export PKG_CONFIG_PATH='$(netfilter_pkg_config_path)' && make -j$(nproc)"
    run_cmd bash -lc "cd '$source_dir' && export PKG_CONFIG_PATH='$(netfilter_pkg_config_path)' && make DESTDIR='$stage_root' install"
  else
    (
      export PKG_CONFIG_PATH
      PKG_CONFIG_PATH="$(netfilter_pkg_config_path)"
      cd "$source_dir"
      run_cmd ./configure --prefix=/usr/local
      run_cmd make -j"$(nproc)"
      run_cmd make DESTDIR="$stage_root" install
    )
  fi
  copy_staged_tree "$stage_root" "nftables"
  run_cmd ldconfig
  run_cmd rm -rf -- "$tmpdir"
}

install_latest_aide() {
  resolve_aide_release

  local tmpdir archive_path source_dir stage_root
  tmpdir="$(mktemp -d)"
  archive_path="${tmpdir}/${AIDE_TARBALL}"
  source_dir="${tmpdir}/aide-${AIDE_VERSION}"
  stage_root="${tmpdir}/stage"

  run_cmd curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 300 --silent --show-error -o "$archive_path" "$AIDE_URL"
  run_cmd tar -xzf "$archive_path" -C "$tmpdir"
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    run_cmd bash -lc "cd '$source_dir' && ./configure --prefix=/usr/local"
    run_cmd bash -lc "cd '$source_dir' && make -j$(nproc)"
    run_cmd bash -lc "cd '$source_dir' && make DESTDIR='$stage_root' install"
  else
    (
      cd "$source_dir"
      run_cmd ./configure --prefix=/usr/local
      run_cmd make -j"$(nproc)"
      run_cmd make DESTDIR="$stage_root" install
    )
  fi
  copy_staged_tree "$stage_root" "aide"
  run_cmd ldconfig
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
    if [[ "${DRY_RUN:-0}" -eq 0 ]]; then
      printf '%s\n' "$api_key" >"$CROWDSEC_BOUNCER_KEY_PATH"
      chmod 0600 "$CROWDSEC_BOUNCER_KEY_PATH"
    fi
    CROWDSEC_BOUNCER_API_KEY="$api_key"
  fi
  export CROWDSEC_BOUNCER_API_KEY
}

render_all_configs() {
  run_cmd install -d -m 0755 "$NFTABLES_RULES_DIR" "$NFTABLES_DROPIN_DIR" /etc/crowdsec/acquis.d /etc/crowdsec/bouncers "$AIDE_CONF_DIR" "$AIDE_DB_DIR"

  write_text_file "$NFTABLES_CONF_PATH" $'flush ruleset\ninclude "/etc/nftables.d/*.nft"\n'

  write_text_file "$NFTABLES_CROWDSEC_RULES_PATH" $'table ip crowdsec {\n  set crowdsec-blacklists {\n    type ipv4_addr\n    flags timeout\n  }\n\n  chain crowdsec-chain {\n    type filter hook input priority filter; policy accept;\n    ip saddr @crowdsec-blacklists drop\n  }\n}\n\ntable ip6 crowdsec6 {\n  set crowdsec6-blacklists {\n    type ipv6_addr\n    flags timeout\n  }\n\n  chain crowdsec6-chain {\n    type filter hook input priority filter; policy accept;\n    ip6 saddr @crowdsec6-blacklists drop\n  }\n}\n\ntable inet base-filter {\n  chain input {\n    type filter hook input priority filter + 10; policy accept;\n    ct state invalid drop\n  }\n}\n'

  write_text_file "$NFTABLES_DROPIN_PATH" $'[Service]\nExecStart=\nExecStart=/usr/local/sbin/nft -f /etc/nftables.conf\n'

  render_crowdsec_acquis

  write_text_file "$AIDE_CONF_PATH" $'database_in=file:/var/lib/aide/aide.db.gz\ndatabase_out=file:/var/lib/aide/aide.db.new.gz\ngzip_dbout=yes\nreport_summarize_changes=yes\nreport_grouped=yes\nwarn_dead_symlinks=yes\n\nNORMAL = ftype+p+u+g+n+s+m+c+acl+xattrs+sha256\nDIR = ftype+p+u+g+n+acl+xattrs\n\n-/dev\n-/proc\n-/run\n-/sys\n-/tmp\n-/var/tmp\n-/var/cache\n-/var/spool\n-/var/log\n-/var/log/journal\n-/var/local\n-/var/swap\n-/data/workspace\n-/data/codex\n-/media\n-/mnt\n-/lost\\+found\n-/var/lib/aide\n-/var/lib/crowdsec\n-/var/lib/containerd\n-/var/lib/docker\n-/var/lib/containers\n-/var/lib/systemd/coredump\n\n/etc$ DIR\n/etc/ NORMAL\n/usr$ DIR\n/usr/ NORMAL\n/usr/local$ DIR\n/usr/local/ NORMAL\n/boot$ DIR\n/boot/ NORMAL\n/opt$ DIR\n/opt/ NORMAL\n/root$ DIR\n/root/ NORMAL\n/var/lib/systemd$ DIR\n/var/lib/systemd/ NORMAL\n/var/lib/dpkg$ DIR\n/var/lib/dpkg/ NORMAL\n'

  write_text_file "$AIDE_CHECK_SERVICE_PATH" $'[Unit]\nDescription=05-security AIDE integrity check\nWants=network-online.target\nAfter=network-online.target\n\n[Service]\nType=oneshot\nExecStart=/usr/local/bin/aide --config=/etc/aide/aide.conf --check\nNice=19\nIOSchedulingClass=best-effort\nIOSchedulingPriority=7\n'

  write_text_file "$AIDE_CHECK_TIMER_PATH" "[Unit]
Description=05-security AIDE scheduled integrity check

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

initialize_nftables() {
  run_cmd systemctl enable --now nftables.service
}

initialize_crowdsec() {
  run_cmd systemctl enable --now crowdsec.service
  run_cmd cscli collections install crowdsecurity/linux crowdsecurity/sshd
  ensure_crowdsec_bouncer_key
  write_text_file "$CROWDSEC_BOUNCER_LOCAL_PATH" "mode: nftables
api_url: http://127.0.0.1:8080/
api_key: ${CROWDSEC_BOUNCER_API_KEY}
update_frequency: 10s
deny_action: DROP
nftables:
  ipv4:
    enabled: true
    set-only: true
    table: crowdsec
    chain: crowdsec-chain
  ipv6:
    enabled: true
    set-only: true
    table: crowdsec6
    chain: crowdsec6-chain
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

enable_security_services() {
  run_cmd systemctl enable --now crowdsec-firewall-bouncer.service
  run_cmd systemctl enable --now 05-security-aide-check.timer
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
  verify_path_exists "$CROWDSEC_LIST_PATH"
  verify_path_exists "$CROWDSEC_PREFS_PATH"
  verify_path_exists "$NFTABLES_CONF_PATH"
  verify_path_exists "$NFTABLES_CROWDSEC_RULES_PATH"
  verify_path_exists "$NFTABLES_DROPIN_PATH"
  verify_path_exists "$CROWDSEC_ACQUIS_PATH"
  verify_path_exists "$CROWDSEC_BOUNCER_LOCAL_PATH"
  verify_path_exists "$AIDE_CONF_PATH"
  verify_path_exists "$AIDE_DB_PATH"
  verify_path_exists "$AIDE_CHECK_SERVICE_PATH"
  verify_path_exists "$AIDE_CHECK_TIMER_PATH"
  verify_path_exists "${MANIFEST_ROOT}/nftables.files"
  verify_path_exists "${MANIFEST_ROOT}/aide.files"
  verify_path_exists "${MANIFEST_ROOT}/libmnl.files"
  verify_path_exists "${MANIFEST_ROOT}/libnftnl.files"

  for cmd in /usr/local/sbin/nft /usr/local/bin/aide crowdsec cscli crowdsec-firewall-bouncer; do
    command_is_available "$cmd" || die "missing command: $cmd"
  done

  resolve_nftables_release
  installed_nft_version="$(/usr/local/sbin/nft --version 2>/dev/null | grep -o '[0-9][0-9.]*' | head -n1)"
  [[ "$installed_nft_version" == "$NFTABLES_VERSION" ]] || die "expected nftables ${NFTABLES_VERSION}, found ${installed_nft_version:-unknown}"

  resolve_aide_release
  installed_aide_version="$(/usr/local/bin/aide --version 2>/dev/null | grep -o '[0-9][0-9.]*' | head -n1)"
  [[ "$installed_aide_version" == "$AIDE_VERSION" ]] || die "expected AIDE ${AIDE_VERSION}, found ${installed_aide_version:-unknown}"

  resolve_crowdsec_release
  installed_crowdsec_version="$(crowdsec -version 2>/dev/null | grep -o '[0-9][0-9.]*' | head -n1)"
  [[ "$installed_crowdsec_version" == "$CROWDSEC_VERSION" ]] || die "expected CrowdSec ${CROWDSEC_VERSION}, found ${installed_crowdsec_version:-unknown}"

  resolve_crowdsec_bouncer_release
  installed_bouncer_version="$(crowdsec-firewall-bouncer -version 2>/dev/null | grep -o '[0-9][0-9.]*' | head -n1)"
  [[ "$installed_bouncer_version" == "$CROWDSEC_BOUNCER_VERSION" ]] || die "expected firewall bouncer ${CROWDSEC_BOUNCER_VERSION}, found ${installed_bouncer_version:-unknown}"

  grep -F 'set-only: true' "$CROWDSEC_BOUNCER_LOCAL_PATH" >/dev/null || die "bouncer config missing nftables set-only mode"
  grep -F '/data/workspace' "$AIDE_CONF_PATH" >/dev/null || die "AIDE config missing /data/workspace exclusion"
  grep -F '/var/log' "$AIDE_CONF_PATH" >/dev/null || die "AIDE config missing /var/log exclusion"
  grep -F '/tmp' "$AIDE_CONF_PATH" >/dev/null || die "AIDE config missing /tmp exclusion"

  systemctl is-enabled nftables.service >/dev/null 2>&1 || die "nftables.service is not enabled"
  systemctl is-enabled crowdsec.service >/dev/null 2>&1 || die "crowdsec.service is not enabled"
  systemctl is-enabled crowdsec-firewall-bouncer.service >/dev/null 2>&1 || die "crowdsec-firewall-bouncer.service is not enabled"
  systemctl is-enabled 05-security-aide-check.timer >/dev/null 2>&1 || die "05-security-aide-check.timer is not enabled"
}

remove_security_install() {
  run_cmd systemctl disable --now 05-security-aide-check.timer >/dev/null 2>&1 || true
  run_cmd systemctl disable --now crowdsec-firewall-bouncer.service >/dev/null 2>&1 || true
  run_cmd systemctl disable --now crowdsec.service >/dev/null 2>&1 || true
  run_cmd systemctl disable --now nftables.service >/dev/null 2>&1 || true

  remove_manifest_files "${MANIFEST_ROOT}/aide.files"
  remove_manifest_files "${MANIFEST_ROOT}/nftables.files"
  remove_manifest_files "${MANIFEST_ROOT}/libmnl.files"
  remove_manifest_files "${MANIFEST_ROOT}/libnftnl.files"
  run_cmd rm -rf -- "$MANIFEST_ROOT"

  run_cmd rm -f -- "$CROWDSEC_KEYRING_PATH" "$CROWDSEC_LIST_PATH" "$CROWDSEC_PREFS_PATH"
  run_cmd rm -f -- "$NFTABLES_CONF_PATH" "$NFTABLES_CROWDSEC_RULES_PATH" "$NFTABLES_DROPIN_PATH"
  run_cmd rmdir --ignore-fail-on-non-empty "$NFTABLES_DROPIN_DIR" >/dev/null 2>&1 || true
  run_cmd rmdir --ignore-fail-on-non-empty "$NFTABLES_RULES_DIR" >/dev/null 2>&1 || true
  run_cmd rm -f -- "$CROWDSEC_ACQUIS_PATH" "$CROWDSEC_BOUNCER_LOCAL_PATH" "$CROWDSEC_BOUNCER_KEY_PATH" "$CROWDSEC_CONSOLE_MARKER"
  run_cmd rm -f -- "$AIDE_CONF_PATH" "$AIDE_CHECK_SERVICE_PATH" "$AIDE_CHECK_TIMER_PATH" "$AIDE_DB_PATH" "$AIDE_DB_NEW_PATH"
  run_cmd rmdir --ignore-fail-on-non-empty "$AIDE_CONF_DIR" >/dev/null 2>&1 || true
  run_cmd rmdir --ignore-fail-on-non-empty "$AIDE_DB_DIR" >/dev/null 2>&1 || true

  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive apt remove "${apt_args[@]}" crowdsec crowdsec-firewall-bouncer-nftables nftables || true
  run_cmd ldconfig
  systemd_daemon_reload
}
