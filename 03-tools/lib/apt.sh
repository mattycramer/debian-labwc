#!/usr/bin/env bash

readonly SID_SUITE="sid"
readonly NORMAL_BOOTSTRAP_PACKAGES=(
  apt-transport-https
  ca-certificates
  wget
  gpg
  curl
  desktop-file-utils
)

readonly NORMAL_TOOLS_PACKAGES=(
  code
  mullvad-browser-alpha
  mullvad-vpn
  spotify-client
)

readonly SID_TOOLS_PACKAGES=(
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

readonly TOOLS_KEYRING_DIR="/usr/share/keyrings"
readonly SPOTIFY_KEY_URL="https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.asc"
readonly SPOTIFY_KEYRING_PATH="${TOOLS_KEYRING_DIR}/spotify.gpg"
readonly SPOTIFY_LIST_PATH="/etc/apt/sources.list.d/spotify.list"
readonly SPOTIFY_SOURCES_PATH="/etc/apt/sources.list.d/spotify.sources"
readonly CODE_WRAPPER_PATH="/usr/local/bin/code"
readonly CODE_DESKTOP_OVERRIDE_PATH="/usr/local/share/applications/code.desktop"
readonly BITWARDEN_WRAPPER_PATH="/usr/local/bin/bitwarden"
readonly BITWARDEN_DESKTOP_OVERRIDE_PATH="/usr/local/share/applications/bitwarden.desktop"

apt_yes_args() {
  if [[ "${ASSUME_YES:-1}" -eq 1 ]]; then
    printf '%s\n' "-y"
  fi
}

detect_tools_target_user() {
  if [[ -n "${SUDO_USER:-}" ]] && [[ "${SUDO_USER:-}" != "root" ]] && id "${SUDO_USER:-}" >/dev/null 2>&1; then
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
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt -t "$SID_SUITE" install --no-install-recommends "${apt_args[@]}" "${NORMAL_BOOTSTRAP_PACKAGES[@]}"
}

prepare_tools_download_path() {
  local path="$1"
  local path_dir
  [[ "$path" == /tmp/* ]] || die "download path must stay under /tmp: $path"
  path_dir="$(dirname "$path")"
  run_cmd runuser -u "$TOOLS_TARGET_USER" -- mkdir -p "$path_dir"
  run_cmd runuser -u "$TOOLS_TARGET_USER" -- rm -f -- "$path"
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

remove_spotify_legacy_source_list() {
  run_cmd rm -f "$SPOTIFY_LIST_PATH"
}

install_spotify_repository_files() {
  local spotify_key_asc="/tmp/spotify-key.asc"
  run_cmd install -d -m 0755 "$TOOLS_KEYRING_DIR"
  download_as_tools_user "$SPOTIFY_KEY_URL" "$spotify_key_asc"
  run_cmd gpg --dearmor --yes --output "$SPOTIFY_KEYRING_PATH" "$spotify_key_asc"
  run_cmd chmod 0644 "$SPOTIFY_KEYRING_PATH"
  run_cmd rm -f -- "$spotify_key_asc"
  remove_spotify_legacy_source_list
  printf '%s' 'Types: deb
URIs: https://repository.spotify.com
Suites: stable
Components: non-free
Architectures: amd64
Signed-By: /usr/share/keyrings/spotify.gpg
' > "$SPOTIFY_SOURCES_PATH"
  run_cmd chmod 0644 "$SPOTIFY_SOURCES_PATH"
}

install_repository_files() {
  local microsoft_key_asc="/tmp/microsoft-packages.asc"
  local microsoft_key_gpg="${TOOLS_KEYRING_DIR}/microsoft.gpg"
  local mullvad_key_asc="/tmp/mullvad-keyring.asc"
  local mullvad_key_gpg="${TOOLS_KEYRING_DIR}/mullvad-keyring.gpg"
  run_cmd install -d -m 0755 "$TOOLS_KEYRING_DIR"
  download_as_tools_user "https://packages.microsoft.com/keys/microsoft.asc" "$microsoft_key_asc"
  run_cmd gpg --dearmor --yes --output "$microsoft_key_gpg" "$microsoft_key_asc"
  run_cmd chmod 0644 "$microsoft_key_gpg"
  run_cmd rm -f -- "$microsoft_key_asc"
  printf '%s' 'Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/microsoft.gpg
' > /etc/apt/sources.list.d/vscode.sources
  run_cmd chmod 0644 /etc/apt/sources.list.d/vscode.sources

  download_as_tools_user "https://repository.mullvad.net/deb/mullvad-keyring.asc" "$mullvad_key_asc"
  run_cmd gpg --dearmor --yes --output "$mullvad_key_gpg" "$mullvad_key_asc"
  run_cmd chmod 0644 "$mullvad_key_gpg"
  run_cmd rm -f -- "$mullvad_key_asc"
  printf '%s' 'Types: deb
URIs: https://repository.mullvad.net/deb/stable
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/mullvad-keyring.gpg
' > /etc/apt/sources.list.d/mullvad.sources
  run_cmd chmod 0644 /etc/apt/sources.list.d/mullvad.sources

  install_spotify_repository_files
}

install_normal_tools() {
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt -t "$SID_SUITE" install --no-install-recommends "${apt_args[@]}" "${NORMAL_TOOLS_PACKAGES[@]}"
  remove_spotify_legacy_source_list
}

install_sid_tools() {
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt -t "$SID_SUITE" install --no-install-recommends "${apt_args[@]}" "${SID_TOOLS_PACKAGES[@]}"
}

install_deb_url() {
  local url="$1"
  local output_path="$2"
  local -a apt_args=()
  [[ -n "$url" ]] || die "missing deb download url"
  [[ "$output_path" == *.deb ]] || die "deb output path must end in .deb: $output_path"
  mapfile -t apt_args < <(apt_yes_args)
  download_as_tools_user "$url" "$output_path"
  dpkg-deb -f "$output_path" Package >/dev/null 2>&1 || die "downloaded file is not a valid Debian package: $output_path"
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt -t "$SID_SUITE" install "${apt_args[@]}" "$output_path"
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
  render_code_kwallet_wrapper
  render_bitwarden_wayland_wrapper
  refresh_managed_desktop_database
}

render_code_kwallet_wrapper() {
  run_cmd install -d -m 0755 /usr/local/bin /usr/local/share/applications
  cat >"$CODE_WRAPPER_PATH" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

app_command='/usr/share/code/code'

if [[ ! -x "$app_command" ]]; then
  printf 'missing Code launcher: %s\n' "$app_command" >&2
  exit 1
fi

unset USE_X11
export ELECTRON_OZONE_PLATFORM_HINT=wayland
if [[ -n "${WAYLAND_DISPLAY:-}" && "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
  unset DISPLAY
fi

exec "$app_command" \
  --password-store=kwallet6 \
  --enable-features=UseOzonePlatform,WaylandWindowDecorations \
  --ozone-platform=wayland \
  "$@"
EOF
  run_cmd chmod 0755 "$CODE_WRAPPER_PATH"

  cat >"$CODE_DESKTOP_OVERRIDE_PATH" <<'EOF'
[Desktop Entry]
Name=Visual Studio Code
Comment=Code Editing. Redefined.
GenericName=Text Editor
Exec=/usr/local/bin/code %F
Icon=vscode
Type=Application
StartupNotify=false
StartupWMClass=Code
Categories=TextEditor;Development;IDE;
MimeType=application/x-code-workspace;
Actions=new-empty-window;
Keywords=vscode;

[Desktop Action new-empty-window]
Name=New Empty Window
Exec=/usr/local/bin/code --new-window %F
Icon=vscode
EOF
  run_cmd chmod 0644 "$CODE_DESKTOP_OVERRIDE_PATH"
}

render_bitwarden_wayland_wrapper() {
  run_cmd install -d -m 0755 /usr/local/bin /usr/local/share/applications
  cat >"$BITWARDEN_WRAPPER_PATH" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

app_command='/opt/Bitwarden/bitwarden-app'

if [[ ! -x "$app_command" ]]; then
  printf 'missing Bitwarden launcher: %s\n' "$app_command" >&2
  exit 1
fi

unset USE_X11
export ELECTRON_OZONE_PLATFORM_HINT=wayland
if [[ -n "${WAYLAND_DISPLAY:-}" && "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
  unset DISPLAY
fi

exec "$app_command" \
  --password-store=kwallet6 \
  --enable-features=UseOzonePlatform,WaylandWindowDecorations \
  --ozone-platform=wayland \
  "$@"
EOF
  run_cmd chmod 0755 "$BITWARDEN_WRAPPER_PATH"

  cat >"$BITWARDEN_DESKTOP_OVERRIDE_PATH" <<'EOF'
[Desktop Entry]
Name=Bitwarden
Exec=/usr/local/bin/bitwarden %U
Terminal=false
Type=Application
Icon=bitwarden
StartupWMClass=Bitwarden
GenericName=Password Manager
Comment=A secure and free password manager for all of your devices.
MimeType=x-scheme-handler/bitwarden;
Categories=Utility;
EOF
  run_cmd chmod 0644 "$BITWARDEN_DESKTOP_OVERRIDE_PATH"
}

refresh_managed_desktop_database() {
  if command -v update-desktop-database >/dev/null 2>&1; then
    run_cmd update-desktop-database /usr/local/share/applications
  fi
}

render_mpv_config() {
  run_cmd install -d -m 0755 -o "$TOOLS_TARGET_USER" -g "$TOOLS_TARGET_USER" \
    "$TOOLS_TARGET_HOME/.config" \
    "$TOOLS_TARGET_HOME/.local"
  run_cmd chown -R "$TOOLS_TARGET_USER:$TOOLS_TARGET_USER" "$TOOLS_TARGET_HOME/.config" "$TOOLS_TARGET_HOME/.local"
  local config_dir="$TOOLS_TARGET_HOME/.config/mpv"
  run_cmd install -d -m 0755 -o "$TOOLS_TARGET_USER" -g "$TOOLS_TARGET_USER" "$config_dir"
  run_cmd install -m 0644 -o "$TOOLS_TARGET_USER" -g "$TOOLS_TARGET_USER" /dev/null "$config_dir/mpv.conf"
  run_cmd runuser -u "$TOOLS_TARGET_USER" -- sh -c "printf '%s\n' 'vo=gpu' 'gpu-api=opengl' 'hwdec=auto-safe' > '$config_dir/mpv.conf'"
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
  for pkg in "${NORMAL_TOOLS_PACKAGES[@]}" "${SID_TOOLS_PACKAGES[@]}"; do
    package_is_installed "$pkg" || die "package '$pkg' is not installed"
  done
  package_is_installed thorium-browser || die "thorium-browser package is not installed"
  package_is_installed bitwarden || die "bitwarden package is not installed"
  package_pattern_installed '^obsidian($|[-])' || die "obsidian package is not installed"
  package_pattern_installed 'filen' || die "filen package is not installed"
  [[ -f "/etc/apt/sources.list.d/vscode.sources" ]] || die "missing vscode.sources"
  [[ -f "/etc/apt/sources.list.d/mullvad.sources" ]] || die "missing mullvad.sources"
  [[ -f "$SPOTIFY_SOURCES_PATH" ]] || die "missing spotify.sources"
  [[ ! -e "$SPOTIFY_LIST_PATH" ]] || die "legacy spotify.list exists; spotify must use a deb822 .sources file"
  [[ -f "/usr/share/keyrings/microsoft.gpg" ]] || die "missing microsoft keyring"
  [[ -f "/usr/share/keyrings/mullvad-keyring.gpg" ]] || die "missing mullvad keyring"
  [[ -f "$SPOTIFY_KEYRING_PATH" ]] || die "missing spotify keyring"
  grep -F 'Architectures: amd64' /etc/apt/sources.list.d/vscode.sources >/dev/null || die "vscode source missing amd64 architecture"
  grep -F 'Signed-By: /usr/share/keyrings/microsoft.gpg' /etc/apt/sources.list.d/vscode.sources >/dev/null || die "vscode source missing microsoft signed-by key"
  grep -F 'URIs: https://packages.microsoft.com/repos/code' /etc/apt/sources.list.d/vscode.sources >/dev/null || die "vscode source missing expected repo uri"
  grep -F 'Suites: stable' /etc/apt/sources.list.d/vscode.sources >/dev/null || die "vscode source missing stable suite"
  grep -F 'Components: main' /etc/apt/sources.list.d/vscode.sources >/dev/null || die "vscode source missing main component"
  grep -F 'Architectures: amd64' /etc/apt/sources.list.d/mullvad.sources >/dev/null || die "mullvad source missing amd64 architecture"
  grep -F 'Signed-By: /usr/share/keyrings/mullvad-keyring.gpg' /etc/apt/sources.list.d/mullvad.sources >/dev/null || die "mullvad source missing mullvad signed-by key"
  grep -F 'URIs: https://repository.mullvad.net/deb/stable' /etc/apt/sources.list.d/mullvad.sources >/dev/null || die "mullvad source missing expected repo uri"
  grep -F 'Suites: stable' /etc/apt/sources.list.d/mullvad.sources >/dev/null || die "mullvad source missing stable suite"
  grep -F 'Components: main' /etc/apt/sources.list.d/mullvad.sources >/dev/null || die "mullvad source missing main component"
  grep -F 'Architectures: amd64' "$SPOTIFY_SOURCES_PATH" >/dev/null || die "spotify source missing amd64 architecture"
  grep -F 'Signed-By: /usr/share/keyrings/spotify.gpg' "$SPOTIFY_SOURCES_PATH" >/dev/null || die "spotify source missing dedicated signed-by key"
  grep -F 'URIs: https://repository.spotify.com' "$SPOTIFY_SOURCES_PATH" >/dev/null || die "spotify source missing expected repo uri"
  grep -F 'Suites: stable' "$SPOTIFY_SOURCES_PATH" >/dev/null || die "spotify source missing stable suite"
  grep -F 'Components: non-free' "$SPOTIFY_SOURCES_PATH" >/dev/null || die "spotify source missing non-free component"
  [[ -f "$CODE_WRAPPER_PATH" ]] || die "missing managed Code wrapper"
  [[ -f "$CODE_DESKTOP_OVERRIDE_PATH" ]] || die "missing managed Code desktop override"
  [[ -f "$BITWARDEN_WRAPPER_PATH" ]] || die "missing managed Bitwarden wrapper"
  [[ -f "$BITWARDEN_DESKTOP_OVERRIDE_PATH" ]] || die "missing managed Bitwarden desktop override"
  grep -F '/usr/share/code/code' "$CODE_WRAPPER_PATH" >/dev/null || die "managed Code wrapper is not launching the upstream Code binary"
  grep -F -- '--password-store=kwallet6' "$CODE_WRAPPER_PATH" >/dev/null || die "managed Code wrapper is not forcing KWallet"
  grep -F -- '--ozone-platform=wayland' "$CODE_WRAPPER_PATH" >/dev/null || die "managed Code wrapper is not forcing Wayland"
  grep -F 'Exec=/usr/local/bin/code %F' "$CODE_DESKTOP_OVERRIDE_PATH" >/dev/null || die "managed Code desktop override is missing the wrapper Exec"
  grep -F '/opt/Bitwarden/bitwarden-app' "$BITWARDEN_WRAPPER_PATH" >/dev/null || die "managed Bitwarden wrapper is not launching the Electron binary directly"
  grep -F -- '--password-store=kwallet6' "$BITWARDEN_WRAPPER_PATH" >/dev/null || die "managed Bitwarden wrapper is not forcing KWallet"
  grep -F -- '--ozone-platform=wayland' "$BITWARDEN_WRAPPER_PATH" >/dev/null || die "managed Bitwarden wrapper is not forcing Wayland"
  grep -F 'Exec=/usr/local/bin/bitwarden %U' "$BITWARDEN_DESKTOP_OVERRIDE_PATH" >/dev/null || die "managed Bitwarden desktop override is missing the Wayland wrapper Exec"
  desktop-file-validate "$CODE_DESKTOP_OVERRIDE_PATH"
  desktop-file-validate "$BITWARDEN_DESKTOP_OVERRIDE_PATH"
  [[ -f "$TOOLS_TARGET_HOME/.config/mpv/mpv.conf" ]] || die "missing mpv.conf"
  [[ "$(stat -c '%U:%G' "$TOOLS_TARGET_HOME/.config/mpv/mpv.conf")" == "$TOOLS_TARGET_USER:$TOOLS_TARGET_USER" ]] || die "mpv.conf ownership is wrong"
}

remove_tools_install() {
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt remove "${apt_args[@]}" "${NORMAL_TOOLS_PACKAGES[@]}" "${SID_TOOLS_PACKAGES[@]}" thorium-browser bitwarden obsidian filen || true
  run_cmd rm -f /etc/apt/sources.list.d/vscode.sources /etc/apt/sources.list.d/vscode.list /etc/apt/sources.list.d/thorium.sources /etc/apt/sources.list.d/thorium.list /etc/apt/sources.list.d/mullvad.sources /etc/apt/sources.list.d/mullvad.list "$SPOTIFY_SOURCES_PATH"
  remove_spotify_legacy_source_list
  run_cmd rm -f /usr/share/keyrings/microsoft.gpg /usr/share/keyrings/mullvad-keyring.asc /usr/share/keyrings/mullvad-keyring.gpg "$SPOTIFY_KEYRING_PATH"
  run_cmd rm -f "$CODE_WRAPPER_PATH" "$CODE_DESKTOP_OVERRIDE_PATH"
  run_cmd rm -f "$BITWARDEN_WRAPPER_PATH" "$BITWARDEN_DESKTOP_OVERRIDE_PATH"
  run_cmd rm -f "$TOOLS_TARGET_HOME/.config/mpv/mpv.conf"
}
