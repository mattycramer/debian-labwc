#!/usr/bin/env bash

readonly NORMAL_BOOTSTRAP_PACKAGES=(
  apt-transport-https
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
)

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
}

apt_update() {
  run_cmd env DEBIAN_FRONTEND=noninteractive apt update -o Acquire::Retries=3 -o Acquire::http::Timeout=20
}

install_repo_bootstrap() {
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive apt install --no-install-recommends "${apt_args[@]}" "${NORMAL_BOOTSTRAP_PACKAGES[@]}"
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

install_repository_files() {
  run_cmd bash -lc 'wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/microsoft.gpg'
  run_cmd install -D -o root -g root -m 0644 /tmp/microsoft.gpg /usr/share/keyrings/microsoft.gpg
  run_cmd rm -f /tmp/microsoft.gpg
  write_text_file "/etc/apt/sources.list.d/vscode.sources" $'Types: deb\nURIs: https://packages.microsoft.com/repos/code\nSuites: stable\nComponents: main\nArchitectures: amd64\nSigned-By: /usr/share/keyrings/microsoft.gpg\n'
  run_cmd rm -f /etc/apt/sources.list.d/thorium.sources /etc/apt/sources.list.d/thorium.list

  run_cmd curl -fsSLo /usr/share/keyrings/mullvad-keyring.asc https://repository.mullvad.net/deb/mullvad-keyring.asc
  write_text_file "/etc/apt/sources.list.d/mullvad.sources" $'Types: deb\nURIs: https://repository.mullvad.net/deb/stable\nSuites: stable\nComponents: main\nArchitectures: amd64\nSigned-By: /usr/share/keyrings/mullvad-keyring.asc\n'
}

install_normal_tools() {
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive apt install --no-install-recommends "${apt_args[@]}" "${NORMAL_TOOLS_PACKAGES[@]}"
}

install_backports_tools() {
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive apt -t trixie-backports install --no-install-recommends "${apt_args[@]}" "${BACKPORTS_TOOLS_PACKAGES[@]}"
}

install_deb_url() {
  local url="$1"
  local output_path="$2"
  local -a apt_args=()
  [[ -n "$url" ]] || die "missing deb download url"
  [[ "$output_path" == *.deb ]] || die "deb output path must end in .deb: $output_path"
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 180 --silent --show-error -o "$output_path" "$url"
  if [[ "${DRY_RUN:-0}" -eq 0 ]]; then
    dpkg-deb -f "$output_path" Package >/dev/null 2>&1 || die "downloaded file is not a valid Debian package: $output_path"
  fi
  run_cmd env DEBIAN_FRONTEND=noninteractive apt install "${apt_args[@]}" "$output_path"
  run_cmd rm -f "$output_path"
}

resolve_latest_thorium_url() {
  local index_html
  local latest_deb
  index_html="$(curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 120 --silent --show-error "$THORIUM_INDEX_URL")"
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
  [[ -f "/etc/apt/sources.list.d/mullvad.sources" ]] || die "missing mullvad.sources"
  [[ -f "$TOOLS_TARGET_HOME/.config/mpv/mpv.conf" ]] || die "missing mpv.conf"
  [[ "$(stat -c '%U:%G' "$TOOLS_TARGET_HOME/.config/mpv/mpv.conf")" == "$TOOLS_TARGET_USER:$TOOLS_TARGET_USER" ]] || die "mpv.conf ownership is wrong"
}

remove_tools_install() {
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive apt remove "${apt_args[@]}" "${NORMAL_TOOLS_PACKAGES[@]}" "${BACKPORTS_TOOLS_PACKAGES[@]}" thorium-browser bitwarden obsidian filen || true
  run_cmd rm -f /etc/apt/sources.list.d/vscode.sources /etc/apt/sources.list.d/thorium.sources /etc/apt/sources.list.d/thorium.list /etc/apt/sources.list.d/mullvad.sources
  run_cmd rm -f /usr/share/keyrings/microsoft.gpg /usr/share/keyrings/mullvad-keyring.asc
  run_cmd rm -f "$TOOLS_TARGET_HOME/.config/mpv/mpv.conf"
}
