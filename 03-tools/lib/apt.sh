#!/usr/bin/env bash

readonly NORMAL_BOOTSTRAP_PACKAGES=(
  apt-transport-https
  ca-certificates
  wget
  gpg
  curl
)

readonly NORMAL_TOOLS_PACKAGES=(
  code
  mullvad-browser-alpha
  mullvad-vpn
)

readonly BACKPORTS_TOOLS_PACKAGES=(
  qutebrowser
  mpv
  qbittorrent
  remmina
  mousepad
  bc
  geeqie
  zathura
  aptitude
)

readonly TOOLS_TMP_ROOT="/tmp/debian-labwc-03-tools"
readonly TOOLS_KEYRING_DIR="/usr/share/keyrings"

apt_yes_args() {
  if [[ "${ASSUME_YES:-1}" -eq 1 ]]; then
    printf '%s\n' "-y"
  fi
}

detect_tools_target_user() {
  if [[ -n "${TOOLS_TARGET_USER:-}" ]] && id "$TOOLS_TARGET_USER" >/dev/null 2>&1; then
    :
  elif [[ -n "${SUDO_USER:-}" ]] && [[ "${SUDO_USER:-}" != "root" ]] && id "${SUDO_USER:-}" >/dev/null 2>&1; then
    TOOLS_TARGET_USER="$SUDO_USER"
  else
    TOOLS_TARGET_USER="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /(false|nologin)$/ {print $1; exit}')"
  fi
  [[ -n "$TOOLS_TARGET_USER" ]] || die "could not determine tools target user"
  TOOLS_TARGET_HOME="$(getent passwd "$TOOLS_TARGET_USER" | awk -F: '{print $6}')"
  [[ -n "$TOOLS_TARGET_HOME" ]] || die "could not determine tools target home"
  TOOLS_TARGET_GROUP="$(id -gn "$TOOLS_TARGET_USER")"
  [[ -n "$TOOLS_TARGET_GROUP" ]] || die "could not determine tools target group"
}

apt_update() {
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt update -o Acquire::Retries=3 -o Acquire::http::Timeout=20
}

install_repo_bootstrap() {
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt install --no-install-recommends "${apt_args[@]}" "${NORMAL_BOOTSTRAP_PACKAGES[@]}"
}

write_text_file() {
  local destination="$1"
  local content="$2"
  local temp_file="${TOOLS_TMP_ROOT}/write-text.$$"
  run_cmd install -d -m 1777 /tmp
  run_cmd install -d -m 0755 "$TOOLS_TMP_ROOT"
  printf '%s' "$content" >"$temp_file"
  run_cmd install -D -m 0644 "$temp_file" "$destination"
  rm -f -- "$temp_file"
}

prepare_tools_download_path() {
  local path="$1"
  [[ "$path" == /tmp/* ]] || die "download path must stay under /tmp: $path"
  run_cmd install -d -m 1777 /tmp
  run_cmd install -d -m 0755 -o "$TOOLS_TARGET_USER" -g "$TOOLS_TARGET_GROUP" "$(dirname "$path")"
  run_cmd rm -f -- "$path"
  run_cmd touch "$path"
  run_cmd chown "$TOOLS_TARGET_USER:$TOOLS_TARGET_GROUP" "$path"
  run_cmd chmod 0644 "$path"
}

remove_legacy_source_file_if_matching() {
  local path="$1"
  local needle="$2"
  [[ -f "$path" ]] || return 0
  grep -F "$needle" "$path" >/dev/null || return 0
  run_cmd rm -f -- "$path"
}

download_as_tools_user() {
  local url="$1"
  local path="$2"
  prepare_tools_download_path "$path"
  run_cmd runuser -u "$TOOLS_TARGET_USER" -- env HOME="$TOOLS_TARGET_HOME" TMPDIR=/tmp curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 180 --silent --show-error -o "$path" "$url"
  run_cmd chmod 0644 "$path"
}

fetch_as_tools_user() {
  local url="$1"
  runuser -u "$TOOLS_TARGET_USER" -- env HOME="$TOOLS_TARGET_HOME" TMPDIR=/tmp curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 120 --silent --show-error "$url"
}

install_repository_files() {
  local microsoft_key_asc="/tmp/microsoft-packages.asc"
  local microsoft_key_gpg="/tmp/microsoft-packages.gpg"
  run_cmd install -d -m 0755 "$TOOLS_KEYRING_DIR"
  download_as_tools_user "https://packages.microsoft.com/keys/microsoft.asc" "$microsoft_key_asc"
  run_cmd gpg --dearmor --yes --output "$microsoft_key_gpg" "$microsoft_key_asc"
  run_cmd install -D -o root -g root -m 0644 "$microsoft_key_gpg" "${TOOLS_KEYRING_DIR}/microsoft.gpg"
  run_cmd rm -f -- "$microsoft_key_asc" "$microsoft_key_gpg"
  remove_legacy_source_file_if_matching "/etc/apt/sources.list.d/vscode.list" "packages.microsoft.com/repos/code"
  write_text_file "/etc/apt/sources.list.d/vscode.sources" $'Types: deb\nURIs: https://packages.microsoft.com/repos/code\nSuites: stable\nComponents: main\nArchitectures: amd64\nSigned-By: /usr/share/keyrings/microsoft.gpg\n'

  local mullvad_key="/tmp/mullvad-keyring.asc"
  download_as_tools_user "https://repository.mullvad.net/deb/mullvad-keyring.asc" "$mullvad_key"
  run_cmd install -D -o root -g root -m 0644 "$mullvad_key" "${TOOLS_KEYRING_DIR}/mullvad-keyring.asc"
  run_cmd rm -f -- "$mullvad_key"
  remove_legacy_source_file_if_matching "/etc/apt/sources.list.d/mullvad.sources" "repository.mullvad.net/deb/stable"
  write_text_file "/etc/apt/sources.list.d/mullvad.list" $'deb [signed-by=/usr/share/keyrings/mullvad-keyring.asc arch=amd64] https://repository.mullvad.net/deb/stable stable main\n'
}

install_normal_tools() {
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt install --no-install-recommends "${apt_args[@]}" "${NORMAL_TOOLS_PACKAGES[@]}"
}

install_backports_tools() {
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt -t trixie-backports install --no-install-recommends "${apt_args[@]}" "${BACKPORTS_TOOLS_PACKAGES[@]}"
}

install_deb_url() {
  local url="$1"
  local output_path="$2"
  local -a apt_args=()
  [[ -n "$url" ]] || die "missing deb download url"
  [[ "$output_path" == *.deb ]] || die "deb output path must end in .deb: $output_path"
  mapfile -t apt_args < <(apt_yes_args)
  download_as_tools_user "$url" "$output_path"
  if [[ "${DRY_RUN:-0}" -eq 0 ]]; then
    dpkg-deb -f "$output_path" Package >/dev/null 2>&1 || die "downloaded file is not a valid Debian package: $output_path"
  fi
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt install "${apt_args[@]}" "$output_path"
  run_cmd rm -f "$output_path"
}

resolve_latest_thorium_url() {
  local index_html
  local latest_deb
  index_html="$(fetch_as_tools_user "$THORIUM_INDEX_URL")"
  latest_deb="$(
    printf '%s' "$index_html" \
      | grep -o 'thorium-browser_[0-9][0-9A-Za-z.+:~-]*_amd64\.deb' \
      | sort -Vu \
      | tail -n1
  )"
  [[ -n "$latest_deb" ]] || die "could not resolve latest Thorium .deb"
  THORIUM_URL="${THORIUM_INDEX_URL}${latest_deb}"
  export THORIUM_URL
}

install_deb_tools() {
  resolve_latest_thorium_url
  install_deb_url "$THORIUM_URL" /tmp/thorium-browser_amd64.deb
  install_deb_url "$BITWARDEN_URL" /tmp/bitwarden_amd64.deb
  install_deb_url "$OBSIDIAN_URL" /tmp/obsidian_amd64.deb
  install_deb_url "$FILEN_URL" /tmp/filen_amd64.deb
}

render_mpv_config() {
  run_cmd install -d -m 0755 -o "$TOOLS_TARGET_USER" -g "$TOOLS_TARGET_USER" \
    "$TOOLS_TARGET_HOME/.config" \
    "$TOOLS_TARGET_HOME/.local"
  run_cmd chown -R "$TOOLS_TARGET_USER:$TOOLS_TARGET_USER" "$TOOLS_TARGET_HOME/.config" "$TOOLS_TARGET_HOME/.local"
  local config_dir="$TOOLS_TARGET_HOME/.config/mpv"
  run_cmd install -d -m 0755 -o "$TOOLS_TARGET_USER" -g "$TOOLS_TARGET_USER" "$config_dir"
  printf '%s\n' 'vo=gpu' 'gpu-api=opengl' 'hwdec=auto-safe' > /tmp/mpv.conf.codex
  run_cmd install -m 0644 -o "$TOOLS_TARGET_USER" -g "$TOOLS_TARGET_USER" /tmp/mpv.conf.codex "$config_dir/mpv.conf"
  run_cmd rm -f /tmp/mpv.conf.codex
}

package_is_installed() {
  dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null | grep -F "install ok installed" >/dev/null
}

package_pattern_installed() {
  local pattern="$1"
  dpkg-query -W 2>/dev/null | awk '{print $1}' | grep -Ei "$pattern" >/dev/null
}

verify_tools_install() {
  local pkg
  for pkg in "${NORMAL_TOOLS_PACKAGES[@]}" "${BACKPORTS_TOOLS_PACKAGES[@]}"; do
    package_is_installed "$pkg" || die "package '$pkg' is not installed"
  done
  package_is_installed thorium-browser || die "thorium-browser package is not installed"
  package_is_installed bitwarden || die "bitwarden package is not installed"
  package_pattern_installed '^obsidian($|[-])' || die "obsidian package is not installed"
  package_pattern_installed 'filen' || die "filen package is not installed"
  [[ -f "/etc/apt/sources.list.d/vscode.sources" ]] || die "missing vscode.sources"
  [[ -f "/etc/apt/sources.list.d/mullvad.list" ]] || die "missing mullvad.list"
  [[ -f "/usr/share/keyrings/microsoft.gpg" ]] || die "missing microsoft keyring"
  [[ -f "/usr/share/keyrings/mullvad-keyring.asc" ]] || die "missing mullvad keyring"
  grep -F 'Architectures: amd64' /etc/apt/sources.list.d/vscode.sources >/dev/null || die "vscode source missing amd64 architecture"
  grep -F 'Signed-By: /usr/share/keyrings/microsoft.gpg' /etc/apt/sources.list.d/vscode.sources >/dev/null || die "vscode source missing microsoft signed-by key"
  grep -F 'URIs: https://packages.microsoft.com/repos/code' /etc/apt/sources.list.d/vscode.sources >/dev/null || die "vscode source missing expected repo uri"
  grep -F 'arch=amd64' /etc/apt/sources.list.d/mullvad.list >/dev/null || die "mullvad source missing amd64 architecture"
  grep -F 'signed-by=/usr/share/keyrings/mullvad-keyring.asc' /etc/apt/sources.list.d/mullvad.list >/dev/null || die "mullvad source missing mullvad signed-by key"
  grep -F 'https://repository.mullvad.net/deb/stable stable main' /etc/apt/sources.list.d/mullvad.list >/dev/null || die "mullvad source missing expected repo uri"
  [[ -f "$TOOLS_TARGET_HOME/.config/mpv/mpv.conf" ]] || die "missing mpv.conf"
  [[ "$(stat -c '%U:%G' "$TOOLS_TARGET_HOME/.config/mpv/mpv.conf")" == "$TOOLS_TARGET_USER:$TOOLS_TARGET_USER" ]] || die "mpv.conf ownership is wrong"
}

remove_tools_install() {
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt remove "${apt_args[@]}" "${NORMAL_TOOLS_PACKAGES[@]}" "${BACKPORTS_TOOLS_PACKAGES[@]}" thorium-browser bitwarden obsidian filen || true
  run_cmd rm -f /etc/apt/sources.list.d/vscode.sources /etc/apt/sources.list.d/vscode.list /etc/apt/sources.list.d/thorium.sources /etc/apt/sources.list.d/thorium.list /etc/apt/sources.list.d/mullvad.sources /etc/apt/sources.list.d/mullvad.list
  run_cmd rm -f /usr/share/keyrings/microsoft.gpg /usr/share/keyrings/mullvad-keyring.asc
  run_cmd rm -f "$TOOLS_TARGET_HOME/.config/mpv/mpv.conf"
}
