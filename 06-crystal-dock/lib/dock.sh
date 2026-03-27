#!/usr/bin/env bash

readonly CRYSTAL_DOCK_AUTOSTART_MARKER_BEGIN="# >>> MANAGED BY 06-crystal-dock >>>"
readonly CRYSTAL_DOCK_AUTOSTART_MARKER_END="# <<< MANAGED BY 06-crystal-dock <<<"
readonly CRYSTAL_DOCK_WRAPPER_PATH="/usr/local/bin/debian-labwc-crystal-dock"
readonly CRYSTAL_DOCK_BIN_PATH="/usr/bin/crystal-dock"
readonly CRYSTAL_DOCK_DESKTOP_PATH="/usr/share/applications/crystal-dock.desktop"
readonly CRYSTAL_DOCK_BUILD_ROOT="/usr/local/src/06-crystal-dock"
readonly CRYSTAL_DOCK_SOURCE_DIR="$CRYSTAL_DOCK_BUILD_ROOT/source"
readonly CRYSTAL_DOCK_BUILD_DIR="$CRYSTAL_DOCK_BUILD_ROOT/build"

readonly CRYSTAL_DOCK_BUILD_PACKAGES=(
  ca-certificates
  curl
  build-essential
  cmake
  pkg-config
  python3
  qt6-base-dev
  qt6-base-private-dev
  qt6-wayland-dev
  liblayershellqtinterface-dev
  libwayland-dev
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
  run_cmd env DEBIAN_FRONTEND=noninteractive apt update -o Acquire::Retries=3 -o Acquire::http::Timeout=20
}

install_crystal_dock_dependencies() {
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive apt install --no-install-recommends "${apt_args[@]}" "${CRYSTAL_DOCK_RUNTIME_PACKAGES[@]}"
  run_cmd env DEBIAN_FRONTEND=noninteractive apt install --no-install-recommends "${apt_args[@]}" "${CRYSTAL_DOCK_BUILD_PACKAGES[@]}"
}

patch_crystal_dock_source_tree() {
  local cmake_path="$CRYSTAL_DOCK_SOURCE_DIR/src/CMakeLists.txt"
  local desktop_env_path="$CRYSTAL_DOCK_SOURCE_DIR/src/desktop/desktop_env.cc"
  local window_system_h_path="$CRYSTAL_DOCK_SOURCE_DIR/src/display/window_system.h"
  local window_system_cc_path="$CRYSTAL_DOCK_SOURCE_DIR/src/display/window_system.cc"
  [[ -f "$cmake_path" ]] || die "missing Crystal Dock CMakeLists.txt after source extract"
  [[ -f "$desktop_env_path" ]] || die "missing Crystal Dock desktop_env.cc after source extract"
  [[ -f "$window_system_h_path" ]] || die "missing Crystal Dock window_system.h after source extract"
  [[ -f "$window_system_cc_path" ]] || die "missing Crystal Dock window_system.cc after source extract"
  run_cmd python3 - "$cmake_path" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()

text = re.sub(
    r'if \(Qt6_VERSION VERSION_GREATER_EQUAL 6\.9\.0\)\n'
    r'  set\(QT_NO_PRIVATE_MODULE_WARNING ON\)\n'
    r'  find_package\(Qt6 REQUIRED COMPONENTS GuiPrivate\)\n'
    r'endif\(\)\n',
    '',
    text,
    count=1,
)
text = text.replace(
    'set(LIBS Qt6::DBus Qt6::GuiPrivate Qt6::Widgets Wayland::Client LayerShellQt::Interface)\n',
    'set(LIBS Qt6::DBus Qt6::Widgets Wayland::Client LayerShellQt::Interface)\n',
    1,
)

exclude_lines = [
    "    desktop/budgie_desktop_env.cc\n",
    "    desktop/hyprland_desktop_env.cc\n",
    "    desktop/kde_desktop_env.cc\n",
    "    desktop/lxqt_desktop_env.cc\n",
    "    desktop/niri_desktop_env.cc\n",
    "    desktop/sway_desktop_env.cc\n",
    "    desktop/wayfire_desktop_env.cc\n",
    "    display/kde_auto_hide_manager.cc\n",
    "    display/kde_virtual_desktop_manager.cc\n",
    "    display/kde_window_manager.cc\n",
    "    display/kde_screen_edge.c\n",
    "    display/plasma_virtual_desktop.c\n",
    "    display/plasma_window_management.c\n",
    "    desktop/budgie_desktop_env.h\n",
    "    desktop/hyprland_desktop_env.h\n",
    "    desktop/kde_desktop_env.h\n",
    "    desktop/lxqt_desktop_env.h\n",
    "    desktop/niri_desktop_env.h\n",
    "    desktop/sway_desktop_env.h\n",
    "    desktop/wayfire_desktop_env.h\n",
    "    display/kde_auto_hide_manager.h\n",
    "    display/kde_virtual_desktop_manager.h\n",
    "    display/kde_window_manager.h\n",
    "    display/kde_screen_edge.h\n",
    "    display/plasma_virtual_desktop.h\n",
    "    display/plasma_window_management.h\n",
]

for line in exclude_lines:
    text = text.replace(line, "")

path.write_text(text)
PY
  run_cmd python3 - "$desktop_env_path" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()

new_get = """DesktopEnv* DesktopEnv::getDesktopEnv() {
  QString currentDesktopEnv = getDesktopEnvName();
  if (currentDesktopEnv == "labwc") {
    static std::unique_ptr<LabwcDesktopEnv> labwc(new LabwcDesktopEnv);
    return labwc.get();
  }

  static std::unique_ptr<DesktopEnv> generic(new DesktopEnv);
  return generic.get();
}
"""

exclude_headers = {
    '#include "budgie_desktop_env.h"',
    '#include "hyprland_desktop_env.h"',
    '#include "kde_desktop_env.h"',
    '#include "lxqt_desktop_env.h"',
    '#include "niri_desktop_env.h"',
    '#include "sway_desktop_env.h"',
    '#include "wayfire_desktop_env.h"',
}
lines = [line for line in text.splitlines(True) if line.rstrip('\n') not in exclude_headers]
text = ''.join(lines)
text, count = re.subn(
    r'DesktopEnv\* DesktopEnv::getDesktopEnv\(\) \{\n.*?\n\}\n',
    new_get,
    text,
    count=1,
    flags=re.S,
)
if count != 1:
    raise SystemExit("expected upstream DesktopEnv::getDesktopEnv block not found")

path.write_text(text)
PY
  run_cmd python3 - "$window_system_h_path" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()

for include in (
    '#include "kde_screen_edge.h"\n',
    '#include "plasma_virtual_desktop.h"\n',
    '#include "plasma_window_management.h"\n',
):
    text = text.replace(include, '')

text = re.sub(
    r'  static org_kde_plasma_virtual_desktop_management\* kde_virtual_desktop_management_;\n'
    r'  static org_kde_plasma_window_management\* kde_window_management_;\n'
    r'  static kde_screen_edge_manager_v1\* kde_screen_edge_manager_;\n\n'
    r'  static zwlr_foreign_toplevel_manager_v1\* wlr_window_manager_;\n',
    '  static zwlr_foreign_toplevel_manager_v1* wlr_window_manager_;\n',
    text,
    count=1,
)

path.write_text(text)
PY
  run_cmd python3 - "$window_system_cc_path" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()

for include in (
    '#include "kde_auto_hide_manager.h"\n',
    '#include "kde_virtual_desktop_manager.h"\n',
    '#include "kde_window_manager.h"\n',
):
    text = text.replace(include, '')

text = re.sub(
    r'org_kde_plasma_virtual_desktop_management\* WindowSystem::kde_virtual_desktop_management_;\n'
    r'org_kde_plasma_window_management\* WindowSystem::kde_window_management_;\n'
    r'kde_screen_edge_manager_v1\* WindowSystem::kde_screen_edge_manager_;\n\n'
    r'zwlr_foreign_toplevel_manager_v1\* WindowSystem::wlr_window_manager_;\n',
    'zwlr_foreign_toplevel_manager_v1* WindowSystem::wlr_window_manager_;\n',
    text,
    count=1,
)

text, count = re.subn(
    r'/\* static \*/ bool WindowSystem::init\(struct wl_display\* display\) \{\n.*?\n\}\n',
    """/* static */ bool WindowSystem::init(struct wl_display* display) {\n  struct wl_registry *registry = wl_display_get_registry(display);\n  wl_registry_add_listener(registry, &registry_listener_, NULL);\n\n  // wait for the \"initial\" set of globals to appear\n  wl_display_roundtrip(display);\n\n  if (!wlr_window_manager_) {\n    std::cerr << \"Failed to bind required Wayland interfaces\" << std::endl;\n    return false;\n  }\n\n  WlrWindowManager::init(wlr_window_manager_);\n  WlrWindowManager::bindWindowManagerFunctions(&windowManager_);\n\n  LayerShellQt::Shell::useLayerShell();\n\n  activityManager_ = std::make_unique<QDBusInterface>(\n      \"org.kde.ActivityManager\", \"/ActivityManager/Activities\",\n      \"org.kde.ActivityManager.Activities\");\n  if (activityManager_->isValid()) {\n    const QDBusReply<QString> reply = activityManager_->call(\"CurrentActivity\");\n    if (reply.isValid()) {\n      WindowSystem::self()->setCurrentActivity(reply.value().toStdString());\n    }\n    connect(activityManager_.get(), SIGNAL(CurrentActivityChanged(QString)),\n            WindowSystem::self(), SLOT(onCurrentActivityChanged(QString)));\n  }\n\n  initScreens();\n\n  return true;\n}\n""",
    text,
    count=1,
    flags=re.S,
)
if count != 1:
    raise SystemExit("expected WindowSystem::init block not found")

text = text.replace(
    "/* static */ bool WindowSystem::hasVirtualDesktopManager() {\n  return kde_virtual_desktop_management_ != nullptr;\n}\n",
    "/* static */ bool WindowSystem::hasVirtualDesktopManager() {\n  return false;\n}\n",
    1,
)
text = text.replace(
    "/* static */ bool WindowSystem::hasAutoHideManager() {\n  return kde_screen_edge_manager_ != nullptr;\n}\n",
    "/* static */ bool WindowSystem::hasAutoHideManager() {\n  return false;\n}\n",
    1,
)

text, count = re.subn(
    r'/\* static \*/ void WindowSystem::registry_global\(\n'
    r'    void\* data,\n'
    r'    struct wl_registry\* registry,\n'
    r'    uint32_t name,\n'
    r'    const char\* interface,\n'
    r'    uint32_t version\) \{\n.*?\n\}\n',
    """/* static */ void WindowSystem::registry_global(\n    void* data,\n    struct wl_registry* registry,\n    uint32_t name,\n    const char* interface,\n    uint32_t version) {\n  if (std::string(interface) == \"zwlr_foreign_toplevel_manager_v1\") {\n    wlr_window_manager_ =\n        reinterpret_cast<zwlr_foreign_toplevel_manager_v1*>(wl_registry_bind(\n            registry, name, &zwlr_foreign_toplevel_manager_v1_interface, 3));\n    if (!wlr_window_manager_) {\n      std::cerr << \"Failed to bind zwlr_foreign_toplevel_manager_v1 Wayland interface\"\n                << std::endl;\n    }\n  }\n}\n""",
    text,
    count=1,
    flags=re.S,
)
if count != 1:
    raise SystemExit("expected WindowSystem::registry_global block not found")

path.write_text(text)
PY
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

install_crystal_dock_from_source() {
  local archive_path
  archive_path="$(mktemp --suffix=.tar.gz)"
  log_info "building Crystal Dock ${CRYSTAL_DOCK_VERSION} from source"
  run_cmd install -d -m 0755 "$CRYSTAL_DOCK_BUILD_ROOT"
  run_cmd rm -rf -- "$CRYSTAL_DOCK_SOURCE_DIR"
  run_cmd rm -rf -- "$CRYSTAL_DOCK_BUILD_DIR"
  run_cmd install -d -m 0755 "$CRYSTAL_DOCK_SOURCE_DIR"
  run_cmd curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 180 --silent --show-error -o "$archive_path" "$CRYSTAL_DOCK_SOURCE_URL"
  run_cmd tar -xzf "$archive_path" -C "$CRYSTAL_DOCK_SOURCE_DIR" --strip-components=1
  run_cmd rm -f -- "$archive_path"
  patch_crystal_dock_source_tree
  run_cmd cmake -S "$CRYSTAL_DOCK_SOURCE_DIR/src" -B "$CRYSTAL_DOCK_BUILD_DIR" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
  run_cmd cmake --build "$CRYSTAL_DOCK_BUILD_DIR" --parallel --target crystal-dock
  run_cmd cmake --install "$CRYSTAL_DOCK_BUILD_DIR"
}

render_wrapper_script() {
  local wrapper
  wrapper="$(cat <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

export XDG_CURRENT_DESKTOP="labwc"
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

  require_file "$CRYSTAL_DOCK_BIN_PATH"
  require_file "$CRYSTAL_DOCK_DESKTOP_PATH"
  require_file "$CRYSTAL_DOCK_WRAPPER_PATH"
  require_file "$appearance_path"
  require_file "$panel_path"
  require_file "$fragment_path"

  grep -F 'XDG_CURRENT_DESKTOP="labwc"' "$CRYSTAL_DOCK_WRAPPER_PATH" >/dev/null || die "wrapper missing labwc desktop override"
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
  run_cmd rm -f -- "$CRYSTAL_DOCK_BIN_PATH"
  run_cmd rm -f -- "$CRYSTAL_DOCK_DESKTOP_PATH"
  run_cmd rm -f -- "$CRYSTAL_DOCK_WRAPPER_PATH"
  run_cmd rm -rf -- "$CRYSTAL_DOCK_SOURCE_DIR"
  run_cmd rm -rf -- "$CRYSTAL_DOCK_BUILD_DIR"
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
