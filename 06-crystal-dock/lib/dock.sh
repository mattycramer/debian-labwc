#!/usr/bin/env bash

readonly CRYSTAL_DOCK_AUTOSTART_MARKER_BEGIN="# >>> MANAGED BY debian-labwc crystal-dock >>>"
readonly CRYSTAL_DOCK_AUTOSTART_MARKER_END="# <<< MANAGED BY debian-labwc crystal-dock <<<"
readonly CRYSTAL_DOCK_WRAPPER_PATH="/usr/local/bin/debian-labwc-crystal-dock"
readonly CRYSTAL_DOCK_BIN_PATH="/usr/bin/crystal-dock"
readonly CRYSTAL_DOCK_DESKTOP_PATH="/usr/share/applications/crystal-dock.desktop"
readonly CRYSTAL_DOCK_DOWNLOAD_DIR="/tmp/crystal-dock"
readonly CRYSTAL_DOCK_SID_SUITE="sid"
readonly CRYSTAL_DOCK_SID_SOURCE_PATH="/etc/apt/sources.list.d/sid.sources"
readonly CRYSTAL_DOCK_SID_PREFERENCES_PATH="/etc/apt/preferences.d/sid"

readonly CRYSTAL_DOCK_BOOTSTRAP_PACKAGES=(
  ca-certificates
  curl
)

readonly CRYSTAL_DOCK_RUNTIME_PACKAGES=(
  liblayershellqtinterface6
  libqt6core6t64
  libqt6dbus6
  libqt6gui6
  libqt6widgets6
  libqt6waylandclient6
  libwayland-client0
)

apt_yes_args() {
  if [[ "${ASSUME_YES:-1}" -eq 1 ]]; then
    printf '%s\n' "-y"
  fi
}

detect_target_user() {
  if [[ -n "${DOCK_TARGET_USER:-}" ]] && id "$DOCK_TARGET_USER" >/dev/null 2>&1; then
    :
  elif [[ -n "${LABWC_TARGET_USER:-}" ]] && id "$LABWC_TARGET_USER" >/dev/null 2>&1; then
    DOCK_TARGET_USER="$LABWC_TARGET_USER"
  elif [[ -n "${SUDO_USER:-}" ]] && [[ "${SUDO_USER:-}" != "root" ]] && id "${SUDO_USER:-}" >/dev/null 2>&1; then
    DOCK_TARGET_USER="$SUDO_USER"
  else
    DOCK_TARGET_USER="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /(false|nologin)$/ {print $1; exit}')"
  fi
  [[ -n "${DOCK_TARGET_USER:-}" ]] || die "could not determine dock target user"
  DOCK_TARGET_HOME="$(getent passwd "$DOCK_TARGET_USER" | awk -F: '{print $6}')"
  [[ -n "${DOCK_TARGET_HOME:-}" ]] || die "could not determine dock target home"
}

apt_update() {
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt update -o Acquire::Retries=3 -o Acquire::http::Timeout=20
}

install_crystal_dock_dependencies() {
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  [[ -f "$CRYSTAL_DOCK_SID_SOURCE_PATH" ]] || die "missing sid source file: $CRYSTAL_DOCK_SID_SOURCE_PATH (run 04-dev first)"
  [[ -f "$CRYSTAL_DOCK_SID_PREFERENCES_PATH" ]] || die "missing sid preferences file: $CRYSTAL_DOCK_SID_PREFERENCES_PATH (run 04-dev first)"
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt -t "$CRYSTAL_DOCK_SID_SUITE" install --no-install-recommends "${apt_args[@]}" "${CRYSTAL_DOCK_BOOTSTRAP_PACKAGES[@]}"
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt -t "$CRYSTAL_DOCK_SID_SUITE" install --no-install-recommends "${apt_args[@]}" "${CRYSTAL_DOCK_RUNTIME_PACKAGES[@]}"
}

install_crystal_dock_package() {
  local -a apt_args=()
  local deb_name deb_path tmp_path
  mapfile -t apt_args < <(apt_yes_args)
  deb_name="${CRYSTAL_DOCK_DEB_URL##*/}"
  deb_path="${CRYSTAL_DOCK_DOWNLOAD_DIR}/${deb_name}"
  tmp_path="${deb_path}.part"
  log_info "installing Crystal Dock ${CRYSTAL_DOCK_VERSION} from pinned .deb release"
  run_cmd install -d -m 0755 -o "$DOCK_TARGET_USER" -g "$DOCK_TARGET_USER" "$CRYSTAL_DOCK_DOWNLOAD_DIR"
  run_cmd rm -f -- "$deb_path" "$tmp_path"
  run_cmd runuser -u "$DOCK_TARGET_USER" -- env HOME="$DOCK_TARGET_HOME" TMPDIR=/tmp curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 180 --silent --show-error -o "$tmp_path" "$CRYSTAL_DOCK_DEB_URL"
  run_cmd mv -- "$tmp_path" "$deb_path"
  run_cmd chown "$DOCK_TARGET_USER:$DOCK_TARGET_USER" "$deb_path"
  run_cmd chmod 0644 "$deb_path"
  if [[ "${DRY_RUN:-0}" -eq 0 ]]; then
    printf '%s  %s\n' "$CRYSTAL_DOCK_DEB_SHA256" "$deb_path" | sha256sum --check --status || die "Crystal Dock deb sha256 mismatch"
    [[ "$(dpkg-deb -f "$deb_path" Package 2>/dev/null)" == "crystal-dock" ]] || die "downloaded package is not crystal-dock"
  fi
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt -t "$CRYSTAL_DOCK_SID_SUITE" install --no-install-recommends "${apt_args[@]}" "$deb_path"
  run_cmd rm -f -- "$deb_path"
}

write_root_file() {
  local destination="$1"
  local mode="$2"
  local content="$3"
  local temp_file
  temp_file="$(mktemp)"
  printf '%s' "$content" >"$temp_file"
  run_cmd install -D -m "$mode" "$temp_file" "$destination"
  run_cmd rm -f -- "$temp_file"
}

write_user_file() {
  local destination="$1"
  local mode="$2"
  local content="$3"
  local temp_file
  temp_file="$(mktemp)"
  printf '%s' "$content" >"$temp_file"
  run_cmd install -D -m "$mode" -o "$DOCK_TARGET_USER" -g "$DOCK_TARGET_USER" "$temp_file" "$destination"
  run_cmd rm -f -- "$temp_file"
}

render_wrapper_script() {
  local wrapper
  wrapper="$(cat <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

export XDG_CURRENT_DESKTOP="labwc:wlroots"
export XDG_SESSION_DESKTOP="labwc"
if [[ -z "${XDG_CONFIG_DIRS:-}" ]]; then
  export XDG_CONFIG_DIRS="/etc/xdg"
elif [[ ":${XDG_CONFIG_DIRS}:" != *":/etc/xdg:"* ]]; then
  export XDG_CONFIG_DIRS="/etc/xdg:${XDG_CONFIG_DIRS}"
fi

exec /usr/bin/crystal-dock "$@"
EOF
)"
  write_root_file "$CRYSTAL_DOCK_WRAPPER_PATH" 0755 "$wrapper"
}

render_labwc_autostart_fragment() {
  local fragment_path="$DOCK_TARGET_HOME/.config/labwc/autostart.d/50-crystal-dock.sh"
  local fragment
  fragment="$(cat <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

command -v /usr/local/bin/debian-labwc-crystal-dock >/dev/null 2>&1 || exit 0
pgrep -x crystal-dock >/dev/null 2>&1 && exit 0
/usr/local/bin/debian-labwc-crystal-dock >/dev/null 2>&1 &
EOF
)"
  write_user_file "$fragment_path" 0755 "$fragment"
}

ensure_labwc_autostart_hook() {
  local autostart_path="$DOCK_TARGET_HOME/.config/labwc/autostart"
  [[ -f "$autostart_path" ]] || return 0
  grep -F '.config/labwc/autostart.d' "$autostart_path" >/dev/null && return 0
  grep -F "$CRYSTAL_DOCK_AUTOSTART_MARKER_BEGIN" "$autostart_path" >/dev/null && return 0
  local hook
  hook="$(cat <<EOF

$CRYSTAL_DOCK_AUTOSTART_MARKER_BEGIN
autostart_dir="$DOCK_TARGET_HOME/.config/labwc/autostart.d"
if [[ -d "\$autostart_dir" ]]; then
  while IFS= read -r -d '' autostart_fragment; do
    bash "\$autostart_fragment" >/dev/null 2>&1 || true
  done < <(find "\$autostart_dir" -maxdepth 1 -type f -name '*.sh' -print0 | sort -z)
fi
$CRYSTAL_DOCK_AUTOSTART_MARKER_END
EOF
)"
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    printf '[dry-run] append managed autostart hook to %s\n' "$autostart_path"
    return 0
  fi
  printf '%s' "$hook" >>"$autostart_path"
  run_cmd chown "$DOCK_TARGET_USER:$DOCK_TARGET_USER" "$autostart_path"
}

render_appearance_config() {
  local path="$DOCK_TARGET_HOME/.config/crystal-dock/labwc/appearance.conf"
  local content
  content="$(cat <<EOF
panelStyle=${CRYSTAL_DOCK_PANEL_STYLE}
minimumIconSize=${CRYSTAL_DOCK_MIN_ICON_SIZE}
maximumIconSize=${CRYSTAL_DOCK_MAX_ICON_SIZE}
spacingFactor=${CRYSTAL_DOCK_SPACING_FACTOR}
tooltipFontSize=${CRYSTAL_DOCK_TOOLTIP_FONT_SIZE}
backgroundColor2D=${CRYSTAL_DOCK_BACKGROUND_COLOR_2D}
borderColor=${CRYSTAL_DOCK_BORDER_COLOR}
activeIndicatorColor2D=${CRYSTAL_DOCK_ACTIVE_INDICATOR_COLOR_2D}
inactiveIndicatorColor2D=${CRYSTAL_DOCK_INACTIVE_INDICATOR_COLOR_2D}
firstRunMultiScreen=false
firstRunWindowCountIndicator=false
bouncingLauncherIcon=false
EOF
)"
  write_user_file "$path" 0644 "$content"
}

render_panel_config() {
  local path="$DOCK_TARGET_HOME/.config/crystal-dock/labwc/panel_1.conf"
  local content
  content="$(cat <<EOF
position=${CRYSTAL_DOCK_POSITION}
visibility=${CRYSTAL_DOCK_VISIBILITY}
screen=0
showApplicationMenu=${CRYSTAL_DOCK_SHOW_APPLICATION_MENU}
showPager=false
showTaskManager=${CRYSTAL_DOCK_SHOW_TASK_MANAGER}
showTrash=${CRYSTAL_DOCK_SHOW_TRASH}
showWifiManager=${CRYSTAL_DOCK_SHOW_WIFI_MANAGER}
showVolumeControl=${CRYSTAL_DOCK_SHOW_VOLUME_CONTROL}
showBatteryIndicator=${CRYSTAL_DOCK_SHOW_BATTERY_INDICATOR}
showKeyboardLayout=${CRYSTAL_DOCK_SHOW_KEYBOARD_LAYOUT}
showVersionChecker=${CRYSTAL_DOCK_SHOW_VERSION_CHECKER}
showClock=${CRYSTAL_DOCK_SHOW_CLOCK}
[TaskManager]
currentDesktopTasksOnly=false
currentScreenTasksOnly=true
groupTasksByApplication=true
EOF
)"
  write_user_file "$path" 0644 "$content"
}

render_crystal_dock_config() {
  run_cmd install -d -m 0755 -o "$DOCK_TARGET_USER" -g "$DOCK_TARGET_USER" \
    "$DOCK_TARGET_HOME/.config" \
    "$DOCK_TARGET_HOME/.config/labwc" \
    "$DOCK_TARGET_HOME/.config/labwc/autostart.d" \
    "$DOCK_TARGET_HOME/.config/crystal-dock" \
    "$DOCK_TARGET_HOME/.config/crystal-dock/labwc"
  render_wrapper_script
  render_appearance_config
  render_panel_config
  render_labwc_autostart_fragment
  ensure_labwc_autostart_hook
  run_cmd chown -R "$DOCK_TARGET_USER:$DOCK_TARGET_USER" \
    "$DOCK_TARGET_HOME/.config/crystal-dock" \
    "$DOCK_TARGET_HOME/.config/labwc/autostart.d"
}

verify_crystal_dock_install() {
  local appearance_path="$DOCK_TARGET_HOME/.config/crystal-dock/labwc/appearance.conf"
  local panel_path="$DOCK_TARGET_HOME/.config/crystal-dock/labwc/panel_1.conf"
  local fragment_path="$DOCK_TARGET_HOME/.config/labwc/autostart.d/50-crystal-dock.sh"

  [[ "$(dpkg-query -W -f='${Status}\n' crystal-dock 2>/dev/null || true)" == *"install ok installed"* ]] || die "crystal-dock package is not installed"
  require_file "$CRYSTAL_DOCK_BIN_PATH"
  require_file "$CRYSTAL_DOCK_DESKTOP_PATH"
  require_file "$CRYSTAL_DOCK_WRAPPER_PATH"
  require_file "$appearance_path"
  require_file "$panel_path"
  require_file "$fragment_path"

  grep -F 'XDG_CURRENT_DESKTOP="labwc:wlroots"' "$CRYSTAL_DOCK_WRAPPER_PATH" >/dev/null || die "wrapper missing labwc/wlroots desktop override"
  grep -F "panelStyle=${CRYSTAL_DOCK_PANEL_STYLE}" "$appearance_path" >/dev/null || die "appearance config missing expected panel style"
  grep -F "position=${CRYSTAL_DOCK_POSITION}" "$panel_path" >/dev/null || die "panel config missing expected position"
  grep -F "showTaskManager=${CRYSTAL_DOCK_SHOW_TASK_MANAGER}" "$panel_path" >/dev/null || die "panel config missing expected task manager state"
  grep -F '/usr/local/bin/debian-labwc-crystal-dock >/dev/null 2>&1 &' "$fragment_path" >/dev/null || die "autostart fragment missing dock launcher"

  if [[ -f "$DOCK_TARGET_HOME/.config/labwc/autostart" ]]; then
    grep -F '.config/labwc/autostart.d' "$DOCK_TARGET_HOME/.config/labwc/autostart" >/dev/null || die "labwc autostart missing autostart.d hook"
  fi

  [[ "$(stat -c '%U:%G' "$appearance_path")" == "$DOCK_TARGET_USER:$DOCK_TARGET_USER" ]] || die "appearance config ownership is wrong"
  [[ "$(stat -c '%U:%G' "$panel_path")" == "$DOCK_TARGET_USER:$DOCK_TARGET_USER" ]] || die "panel config ownership is wrong"
  log_info "verification completed"
}

remove_crystal_dock_install() {
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt remove "${apt_args[@]}" crystal-dock || true
  run_cmd rm -f -- "$CRYSTAL_DOCK_WRAPPER_PATH"
  run_cmd rm -rf -- "$DOCK_TARGET_HOME/.config/crystal-dock"
  run_cmd rm -f -- "$DOCK_TARGET_HOME/.config/labwc/autostart.d/50-crystal-dock.sh"

  local autostart_path="$DOCK_TARGET_HOME/.config/labwc/autostart"
  if [[ -f "$autostart_path" ]]; then
    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
      printf '[dry-run] remove managed autostart hook from %s\n' "$autostart_path"
    else
      sed -i "/$CRYSTAL_DOCK_AUTOSTART_MARKER_BEGIN/,/$CRYSTAL_DOCK_AUTOSTART_MARKER_END/d" "$autostart_path"
      run_cmd chown "$DOCK_TARGET_USER:$DOCK_TARGET_USER" "$autostart_path"
    fi
  fi
}
