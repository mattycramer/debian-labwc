#!/usr/bin/env bash

render_user_file() {
  local destination="$1"
  local content="$2"
  run_cmd install -D -m 0644 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" /dev/null "$destination"
  printf '%s' "$content" >"$destination"
  run_cmd chown "$LABWC_TARGET_USER:$LABWC_TARGET_USER" "$destination"
}

render_user_script() {
  local destination="$1"
  local content="$2"
  run_cmd install -D -m 0755 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" /dev/null "$destination"
  printf '%s' "$content" >"$destination"
  run_cmd chown "$LABWC_TARGET_USER:$LABWC_TARGET_USER" "$destination"
  run_cmd chmod 0755 "$destination"
}

render_runtime_env() {
  local runtime_dir="$LABWC_TARGET_HOME/.config/debian-labwc"
  run_cmd install -d -m 0755 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" "$runtime_dir"
  run_cmd install -m 0644 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" "$1" "$runtime_dir/runtime.env"
}

render_labwc_environment() {
  local environment_file
  environment_file="$(cat <<EOF
XCURSOR_THEME=${LABWC_XCURSOR_THEME}
XCURSOR_SIZE=${LABWC_XCURSOR_SIZE}
EOF
)"
  render_user_file "$LABWC_TARGET_HOME/.config/labwc/environment" "$environment_file"
}

ensure_user_base_dirs() {
  run_cmd install -d -m 0755 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" \
    "$LABWC_TARGET_HOME/.config" \
    "$LABWC_TARGET_HOME/.local" \
    "$LABWC_TARGET_HOME/.local/share"
  run_cmd chown -R "$LABWC_TARGET_USER:$LABWC_TARGET_USER" "$LABWC_TARGET_HOME/.config" "$LABWC_TARGET_HOME/.local"
}

render_home_dirs() {
  local -a dirs=(
    "$LABWC_TARGET_HOME/Desktop"
    "$LABWC_TARGET_HOME/Downloads"
    "$LABWC_TARGET_HOME/Templates"
    "$LABWC_TARGET_HOME/Public"
    "$LABWC_TARGET_HOME/Documents"
    "$LABWC_TARGET_HOME/Music"
    "$LABWC_TARGET_HOME/Pictures"
    "$LABWC_TARGET_HOME/Videos"
  )
  local dir
  for dir in "${dirs[@]}"; do
    run_cmd install -d -m 0755 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" "$dir"
  done
  render_user_file "$LABWC_TARGET_HOME/.config/user-dirs.dirs" $'XDG_DESKTOP_DIR="$HOME/Desktop"\nXDG_DOWNLOAD_DIR="$HOME/Downloads"\nXDG_TEMPLATES_DIR="$HOME/Templates"\nXDG_PUBLICSHARE_DIR="$HOME/Public"\nXDG_DOCUMENTS_DIR="$HOME/Documents"\nXDG_MUSIC_DIR="$HOME/Music"\nXDG_PICTURES_DIR="$HOME/Pictures"\nXDG_VIDEOS_DIR="$HOME/Videos"\n'
  render_user_file "$LABWC_TARGET_HOME/.config/user-dirs.locale" $'en_US.UTF-8\n'
}

render_shell_startup_files() {
  local bashrc profile zshrc zprofile starship
  bashrc="$(cat <<'EOF'
# Managed by debian-labwc
umask 022
export PATH="/data/usr/local/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

if [[ -f /etc/bash_completion ]]; then
  # shellcheck disable=SC1091
  source /etc/bash_completion
elif [[ -f /usr/share/bash-completion/bash_completion ]]; then
  # shellcheck disable=SC1091
  source /usr/share/bash-completion/bash_completion
fi

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi
EOF
)"
  profile="$(cat <<'EOF'
# Managed by debian-labwc
umask 022
export PATH="/data/usr/local/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

if [ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ]; then
  # shellcheck disable=SC1090
  . "$HOME/.bashrc"
fi
EOF
)"
  zshrc="$(cat <<'EOF'
# Managed by debian-labwc
umask 022
export PATH="/data/usr/local/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

autoload -Uz compinit
compinit

if [[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi
EOF
)"
  zprofile="$(cat <<'EOF'
# Managed by debian-labwc
umask 022
export PATH="/data/usr/local/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

if [ -f "$HOME/.profile" ]; then
  . "$HOME/.profile"
fi
EOF
)"
  starship="$(cat <<'EOF'
add_newline = false
format = "$username$hostname$directory$git_branch$git_status\n$character "

[username]
show_always = true
format = "[$user@](bold yellow)"

[hostname]
ssh_only = false
format = "[$hostname ](bold blue)"

[character]
success_symbol = "[>](bold green)"
error_symbol = "[>](bold red)"

[directory]
format = "[$path ](bold cyan)"
home_symbol = "~"
truncation_length = 3
truncate_to_repo = false

[git_branch]
format = "[git:$branch ](bold magenta)"

[git_status]
format = "[$all_status$ahead_behind ](bold red)"
EOF
)"
  render_user_file "$LABWC_TARGET_HOME/.bashrc" "$bashrc"
  render_user_file "$LABWC_TARGET_HOME/.profile" "$profile"
  render_user_file "$LABWC_TARGET_HOME/.zshrc" "$zshrc"
  render_user_file "$LABWC_TARGET_HOME/.zprofile" "$zprofile"
  render_user_file "$LABWC_TARGET_HOME/.config/starship.toml" "$starship"
}

render_xfce_helpers() {
  render_user_file "$LABWC_TARGET_HOME/.config/xfce4/helpers.rc" $'TerminalEmulator=foot\n'
}

render_labwc_rc_xml() {
  case "${LABWC_NATURAL_SCROLL:-}" in
    yes|no) ;;
    *) die "LABWC_NATURAL_SCROLL must be 'yes' or 'no', found '${LABWC_NATURAL_SCROLL:-}'" ;;
  esac
  local title_bind
  title_bind="$(cat <<'EOF'
    <context name="Title">
      <mousebind button="Left" action="DoubleClick">
        <action name="ToggleMaximize" />
      </mousebind>
    </context>
EOF
)"
  local rc_xml
  rc_xml="$(cat <<EOF
<?xml version="1.0"?>
<labwc_config>
  <focus>
    <followMouse>${LABWC_FOLLOW_MOUSE}</followMouse>
    <followMouseRequiresMovement>no</followMouseRequiresMovement>
    <raiseOnFocus>${LABWC_RAISE_ON_FOCUS}</raiseOnFocus>
    <focusDelay>${LABWC_FOCUS_DELAY_MS}</focusDelay>
  </focus>
  <windowSwitcher preview="yes" outlines="yes" unshade="yes" order="focus">
    <osd show="yes" style="classic" output="focused" />
  </windowSwitcher>
  <mouse>
    <default />
    <doubleClickTime>${LABWC_DOUBLECLICK_TIME_MS}</doubleClickTime>
    <context name="Root">
      <mousebind button="Left" action="Press">
        <action name="Unfocus" />
      </mousebind>
    </context>
${title_bind}
  </mouse>
  <libinput>
    <device category="default">
      <naturalScroll>${LABWC_NATURAL_SCROLL}</naturalScroll>
    </device>
    <device category="touchpad">
      <naturalScroll>${LABWC_NATURAL_SCROLL}</naturalScroll>
    </device>
    <device category="non-touch">
      <naturalScroll>${LABWC_NATURAL_SCROLL}</naturalScroll>
    </device>
  </libinput>
  <keyboard>
    <default />
    <keybind key="A-Tab">
      <action name="NextWindow" />
    </keybind>
    <keybind key="A-S-Tab">
      <action name="PreviousWindow" />
    </keybind>
    <keybind key="W-Return">
      <action name="Execute"><command>${LABWC_TERMINAL}</command></action>
    </keybind>
    <keybind key="W-d">
      <action name="Execute"><command>${LABWC_LAUNCHER_CMD}</command></action>
    </keybind>
    <keybind key="W-space">
      <action name="Execute"><command>${LABWC_LAUNCHER_CMD}</command></action>
    </keybind>
    <keybind key="W-e">
      <action name="Execute"><command>thunar</command></action>
    </keybind>
    <keybind key="W-q">
      <action name="Close" />
    </keybind>
    <keybind key="W-l">
      <action name="Execute"><command>swaylock -f</command></action>
    </keybind>
    <keybind key="Print">
      <action name="Execute"><command>/usr/local/bin/debian-labwc-screenshot-full</command></action>
    </keybind>
    <keybind key="S-Print">
      <action name="Execute"><command>/usr/local/bin/debian-labwc-screenshot-region</command></action>
    </keybind>
    <keybind key="W-S-r">
      <action name="Execute"><command>/usr/local/bin/debian-labwc-record-toggle</command></action>
    </keybind>
    <keybind key="W-S-e">
      <action name="Execute"><command>/usr/local/bin/debian-labwc-power-menu</command></action>
    </keybind>
  </keyboard>
</labwc_config>
EOF
)"
  render_user_file "$LABWC_TARGET_HOME/.config/labwc/rc.xml" "$rc_xml"
}

render_labwc_menu_xml() {
  local menu_xml
  menu_xml="$(cat <<'EOF'
<?xml version="1.0"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">
  <menu id="root-menu" label="Applications">
    <item label="Terminal">
      <action name="Execute"><command>footclient</command></action>
    </item>
    <item label="Launcher">
      <action name="Execute"><command>wofi --show drun</command></action>
    </item>
    <item label="Files">
      <action name="Execute"><command>thunar</command></action>
    </item>
    <item label="NNN">
      <action name="Execute"><command>footclient -e nnn</command></action>
    </item>
    <item label="Audio">
      <action name="Execute"><command>pavucontrol</command></action>
    </item>
    <item label="Power">
      <action name="Execute"><command>/usr/local/bin/debian-labwc-power-menu</command></action>
    </item>
  </menu>
</openbox_menu>
EOF
)"
  render_user_file "$LABWC_TARGET_HOME/.config/labwc/menu.xml" "$menu_xml"
}

render_labwc_autostart() {
  local wallpaper_path="$LABWC_TARGET_HOME/.local/share/debian-labwc/labwall2-1920x1080.png"
  local autostart
  autostart="$(cat <<EOF
#!/bin/sh
set -eu
IFS='
	'

export XDG_CURRENT_DESKTOP=labwc:wlroots

pgrep -x foot >/dev/null 2>&1 || foot --server &
pgrep -x swaybg >/dev/null 2>&1 || swaybg -i "$wallpaper_path" -m "${LABWC_WALLPAPER_MODE}" &

attempt=1
while [ "\$attempt" -le 20 ]; do
  if systemctl --user --quiet is-active dbus.service >/dev/null 2>&1; then
    break
  fi
  sleep 1
  attempt=\$((attempt + 1))
done

pgrep -x waybar >/dev/null 2>&1 || waybar &
pgrep -x kanshi >/dev/null 2>&1 || kanshi &
pgrep -x mako >/dev/null 2>&1 || mako &
pgrep -x lxpolkit >/dev/null 2>&1 || lxpolkit &
pgrep -x swayidle >/dev/null 2>&1 || swayidle \
  timeout "${LABWC_IDLE_LOCK_SECONDS}" 'swaylock -f' \
  timeout "${LABWC_IDLE_DPMS_SECONDS}" '/usr/local/bin/debian-labwc-dpms off' \
  resume '/usr/local/bin/debian-labwc-dpms on' \
  before-sleep 'swaylock -f' &

if [ ! -f "$LABWC_TARGET_HOME/.config/debian-labwc/.outputs-refined" ]; then
  /usr/local/bin/debian-labwc-refresh-outputs >/dev/null 2>&1 &
fi

autostart_dir="$LABWC_TARGET_HOME/.config/labwc/autostart.d"
if [ -d "\$autostart_dir" ]; then
  find "\$autostart_dir" -maxdepth 1 -type f -name '*.sh' | sort | while IFS= read -r autostart_fragment; do
    [ -n "\$autostart_fragment" ] || continue
    "\$autostart_fragment" >/dev/null 2>&1 || true
  done
fi
EOF
)"
  render_user_script "$LABWC_TARGET_HOME/.config/labwc/autostart" "$autostart"
}

render_labwc_shutdown() {
  local shutdown
  shutdown="$(cat <<'EOF'
#!/bin/sh
set -eu
IFS='
	'

# Stop session clients first so they do not keep poking D-Bus or PipeWire
# while the compositor and user bus are already shutting down.
pkill -x "waybar" >/dev/null 2>&1 || true
pkill -x "kanshi" >/dev/null 2>&1 || true
pkill -x "mako" >/dev/null 2>&1 || true
pkill -x "lxpolkit" >/dev/null 2>&1 || true
pkill -x "swayidle" >/dev/null 2>&1 || true
pkill -x "crystal-dock" >/dev/null 2>&1 || true
pkill -x "nwg-dock" >/dev/null 2>&1 || true

if command -v gpgconf >/dev/null 2>&1; then
  gpgconf --kill gpg-agent >/dev/null 2>&1 || true
fi
EOF
)"
  render_user_script "$LABWC_TARGET_HOME/.config/labwc/shutdown" "$shutdown"
}

render_gpg_agent_override() {
  render_user_file "$LABWC_TARGET_HOME/.config/systemd/user/gpg-agent.service.d/override.conf" $'[Service]\nTimeoutStopSec=10s\n'
}

render_waybar_config() {
  local waybar
  waybar="$(cat <<'EOF'
{
  "layer": "top",
  "position": "top",
  "height": 42,
  "spacing": 6,
  "modules-left": ["custom/launcher", "ext/workspaces", "wlr/taskbar"],
  "modules-center": ["clock"],
  "modules-right": ["network", "pulseaudio", "battery", "backlight", "cpu", "memory", "disk", "custom/player", "tray", "custom/power"],
  "custom/launcher": {
    "format": "Menu",
    "tooltip": false,
    "on-click": "/usr/local/bin/debian-labwc-launcher-menu",
    "on-click-right": "wofi --show drun"
  },
  "ext/workspaces": {
    "format": "{name}",
    "sort-by-number": true,
    "on-click": "activate"
  },
  "wlr/taskbar": {
    "format": "{app_id}",
    "tooltip-format": "{title}",
    "on-click": "minimize-raise"
  },
  "clock": {
    "interval": 30,
    "format": "{:%a %b %d  %H:%M}",
    "format-alt": "{:%Y-%m-%d  %H:%M:%S}",
    "tooltip-format": "<tt>{:%A %Y-%m-%d\nWeek %V  %Z}</tt>"
  },
  "tray": {
    "spacing": 8
  },
  "network": {
    "interval": 5,
    "family": "ipv4",
    "format-wifi": "WiFi  {essid}",
    "format-ethernet": "LAN  {ifname}",
    "format-linked": "LAN  {ifname} (no ip)",
    "format-disconnected": "Net  offline",
    "format-disabled": "Net  down",
    "tooltip-format-wifi": "{essid}\n{signalStrength}%  {ipaddr}\n↑ {bandwidthUpBytes}  ↓ {bandwidthDownBytes}",
    "tooltip-format-ethernet": "{ifname}\n{ipaddr}\n↑ {bandwidthUpBytes}  ↓ {bandwidthDownBytes}",
    "tooltip-format-disconnected": "Network disconnected",
    "on-click": "/usr/local/bin/debian-labwc-module-menu network quick",
    "on-click-right": "/usr/local/bin/debian-labwc-module-menu network menu"
  },
  "pulseaudio": {
    "format": "Vol  {volume}%",
    "format-muted": "Mute",
    "tooltip-format": "{desc}",
    "scroll-step": 5,
    "reverse-scrolling": true,
    "reverse-mouse-scrolling": true,
    "on-click": "pavucontrol",
    "on-click-middle": "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle",
    "on-click-right": "/usr/local/bin/debian-labwc-module-menu audio menu"
  },
  "battery": {
    "interval": 15,
    "states": {
      "warning": 30,
      "critical": 15
    },
    "format": "Bat  {capacity}%",
    "format-charging": "Charge  {capacity}%",
    "format-full": "Full  {capacity}%",
    "format-warning": "Low  {capacity}%",
    "format-critical": "Crit  {capacity}%",
    "tooltip-format": "{timeTo}\nHealth {health}%  Cycles {cycles}",
    "on-click": "/usr/local/bin/debian-labwc-module-menu battery menu",
    "on-click-right": "/usr/local/bin/debian-labwc-module-menu battery details"
  },
  "backlight": {
    "format": "Bright  {percent}%",
    "scroll-step": 5,
    "tooltip-format": "Brightness {percent}%",
    "reverse-scrolling": true,
    "reverse-mouse-scrolling": true,
    "on-click-right": "/usr/local/bin/debian-labwc-module-menu brightness menu"
  },
  "cpu": {
    "interval": 5,
    "states": {
      "warning": 65,
      "critical": 85
    },
    "format": "CPU  {usage}%",
    "tooltip": true,
    "on-click": "/usr/local/bin/debian-labwc-module-menu system monitor",
    "on-click-right": "/usr/local/bin/debian-labwc-module-menu system menu"
  },
  "memory": {
    "interval": 10,
    "states": {
      "warning": 70,
      "critical": 90
    },
    "format": "RAM  {percentage}%",
    "tooltip-format": "{used:0.1f} GiB / {total:0.1f} GiB\nSwap {swapUsed:0.1f} / {swapTotal:0.1f} GiB",
    "on-click": "/usr/local/bin/debian-labwc-module-menu system monitor",
    "on-click-right": "/usr/local/bin/debian-labwc-module-menu system memory"
  },
  "disk": {
    "interval": 30,
    "path": "/",
    "unit": "GiB",
    "states": {
      "warning": 75,
      "critical": 90
    },
    "format": "Disk  {percentage_used}%",
    "tooltip-format": "{used} used of {total}\n{free} free on {path}",
    "on-click": "/usr/local/bin/debian-labwc-module-menu storage ncdu",
    "on-click-right": "/usr/local/bin/debian-labwc-module-menu storage menu"
  },
  "custom/player": {
    "exec": "/usr/local/bin/debian-labwc-player-status",
    "interval": 2,
    "return-type": "text",
    "max-length": 38,
    "tooltip": false,
    "on-click": "playerctl play-pause",
    "on-click-middle": "playerctl stop",
    "on-click-right": "/usr/local/bin/debian-labwc-module-menu player menu",
    "on-scroll-up": "playerctl next",
    "on-scroll-down": "playerctl previous"
  },
  "custom/power": {
    "format": "Power",
    "tooltip": false,
    "on-click": "/usr/local/bin/debian-labwc-power-menu"
  }
}
EOF
)"
  render_user_file "$LABWC_TARGET_HOME/.config/waybar/config.jsonc" "$waybar"
}

render_waybar_style() {
  local css
  css="$(cat <<'EOF'
* {
  font-family: "Noto Sans", "Font Awesome 6 Free", "Material Design Icons";
  font-size: 13px;
  min-height: 0;
  font-feature-settings: "tnum";
}

window#waybar {
  background: rgba(10, 14, 20, 0.84);
  color: #edf2f7;
  border-bottom: 1px solid rgba(173, 181, 189, 0.16);
}

#workspaces {
  margin: 5px 0;
  padding: 0 4px;
  border-radius: 14px;
  background: rgba(25, 32, 44, 0.74);
  border: 1px solid rgba(88, 101, 119, 0.25);
}

#workspaces button {
  color: #d7dde6;
  padding: 0 12px;
  margin: 4px 2px;
  border-radius: 10px;
  background: transparent;
}

#workspaces button:hover {
  background: rgba(92, 165, 219, 0.18);
  color: #ffffff;
}

#workspaces button.active {
  background: linear-gradient(180deg, rgba(109, 196, 237, 0.92), rgba(71, 167, 214, 0.92));
  color: #09121b;
}

#taskbar {
  margin: 5px 0 5px 8px;
}

#custom-launcher,
#clock,
#network,
#pulseaudio,
#battery,
#backlight,
#cpu,
#memory,
#disk,
#custom-player,
#custom-power,
#tray {
  margin: 5px 0 5px 8px;
  padding: 0 12px;
  min-height: 28px;
  border-radius: 14px;
  background: rgba(25, 32, 44, 0.74);
  border: 1px solid rgba(88, 101, 119, 0.25);
}

#custom-launcher {
  color: #f6bd60;
  font-weight: 600;
}

#clock {
  color: #f3f4f6;
}

#network.disconnected,
#network.disabled {
  color: #f6ad55;
}

#pulseaudio.muted {
  color: #f6ad55;
}

#battery.charging,
#battery.full {
  color: #9ae6b4;
}

#battery.warning,
#cpu.warning,
#memory.warning,
#disk.warning {
  color: #f6e05e;
}

#battery.critical,
#cpu.critical,
#memory.critical,
#disk.critical {
  color: #fc8181;
}

#custom-player {
  color: #c4b5fd;
}

#custom-power {
  background: rgba(68, 25, 33, 0.78);
  border-color: rgba(246, 173, 173, 0.28);
  color: #fed7d7;
  font-weight: 600;
}

#custom-launcher:hover,
#clock:hover,
#network:hover,
#pulseaudio:hover,
#battery:hover,
#backlight:hover,
#cpu:hover,
#memory:hover,
#disk:hover,
#custom-player:hover,
#custom-power:hover,
#tray:hover {
  background: rgba(40, 54, 74, 0.92);
  border-color: rgba(119, 141, 169, 0.38);
}
EOF
)"
  render_user_file "$LABWC_TARGET_HOME/.config/waybar/style.css" "$css"
}

kanshi_output_line() {
  local output_name="$1"
  local mode_name="$2"
  local hz="$3"
  local position="$4"
  local enabled_state="$5"
  local line

  line="  output \"$output_name\""
  if [[ -n "$mode_name" && -n "$hz" ]]; then
    line+=" mode ${mode_name}@${hz}Hz"
  fi
  if [[ -n "$position" ]]; then
    line+=" position ${position}"
  fi
  line+=" ${enabled_state}"
  printf '%s\n' "$line"
}

render_kanshi_config() {
  local internal_output="${LABWC_INTERNAL_OUTPUT:-}"
  local external_output="${LABWC_EXTERNAL_OUTPUT:-}"
  local internal_profile=""
  local external_clause=""

  if [[ -n "$internal_output" ]]; then
    local internal_line
    internal_line="$(kanshi_output_line "$internal_output" "${LABWC_INTERNAL_MODE}" "${LABWC_INTERNAL_HZ}" "0,0" "enable")"
    internal_profile="$(cat <<EOF
profile internal {
${internal_line}
}
EOF
)"
  fi

  if [[ -n "$external_output" ]]; then
    if [[ -n "$internal_output" ]]; then
      local external_line dual_external_line dual_internal_line
      external_line="$(kanshi_output_line "$external_output" "${LABWC_EXTERNAL_MODE}" "${LABWC_EXTERNAL_HZ}" "0,0" "enable")"
      dual_external_line="$(kanshi_output_line "$external_output" "${LABWC_EXTERNAL_MODE}" "${LABWC_EXTERNAL_HZ}" "0,0" "enable")"
      dual_internal_line="$(kanshi_output_line "$internal_output" "${LABWC_INTERNAL_MODE}" "${LABWC_INTERNAL_HZ}" "1920,0" "enable")"
      external_clause="$(cat <<EOF
profile external {
${external_line}
  output "$internal_output" disable
}

profile dual {
${dual_external_line}
${dual_internal_line}
}
EOF
)"
    else
      local external_only_line
      external_only_line="$(kanshi_output_line "$external_output" "${LABWC_EXTERNAL_MODE}" "${LABWC_EXTERNAL_HZ}" "0,0" "enable")"
      external_clause="$(cat <<EOF
profile external {
${external_only_line}
}
EOF
)"
    fi
  fi

  local config
  config="$(cat <<EOF
$internal_profile
$external_clause
EOF
)"
  render_user_file "$LABWC_TARGET_HOME/.config/kanshi/config" "$config"
}

render_wofi() {
  render_user_file "$LABWC_TARGET_HOME/.config/wofi/config" $'show=drun\nwidth=720\nheight=540\nprompt=Run\nallow_images=true\ninsensitive=true\ngtk_dark=true\n'
  render_user_file "$LABWC_TARGET_HOME/.config/wofi/style.css" $'window {\n  margin: 0;\n  padding: 14px;\n  border: 1px solid rgba(111, 124, 143, 0.32);\n  border-radius: 18px;\n  background-color: rgba(12, 17, 24, 0.96);\n}\n#outer-box {\n  padding: 4px;\n}\n#input {\n  margin: 0 0 12px 0;\n  padding: 12px 14px;\n  border-radius: 12px;\n  border: 1px solid rgba(80, 97, 119, 0.35);\n  background-color: rgba(24, 31, 43, 0.92);\n  color: #edf2f7;\n}\n#entry {\n  padding: 10px 12px;\n  border-radius: 12px;\n}\n#entry:selected {\n  background: linear-gradient(180deg, rgba(109, 196, 237, 0.92), rgba(71, 167, 214, 0.92));\n  color: #07111b;\n}\n#text {\n  color: inherit;\n}\n'
}

render_mako() {
  render_user_file "$LABWC_TARGET_HOME/.config/mako/config" $'font=Noto Sans 11\nborder-size=2\npadding=12\ndefault-timeout=5000\nbackground-color=#1b1b1bff\ntext-color=#f5f5f5ff\nborder-color=#4a89dcff\n'
}

render_swaylock() {
  render_user_file "$LABWC_TARGET_HOME/.config/swaylock/config" $'daemonize\nclock\nfont=Noto Sans\nindicator\ncolor=111111\ninside-color=202020\nring-color=4a89dc\nline-color=111111\nkey-hl-color=88c0d0\n'
}

render_foot() {
  render_user_file "$LABWC_TARGET_HOME/.config/foot/foot.ini" $'[main]\nfont=Noto Sans Mono:size=11\npad=8x8\n\n[bell]\nsystem=no\n\n[colors]\nbackground=111111\nforeground=f5f5f5\n'
}

render_gammastep() {
  render_user_file "$LABWC_TARGET_HOME/.config/gammastep/config" $'[general]\nadjustment-method=wayland\n[manual]\nlat=0.0\nlon=0.0\n'
}

render_portals() {
  render_user_file "$LABWC_TARGET_HOME/.config/xdg-desktop-portal/portals.conf" $'[preferred]\ndefault=gtk\norg.freedesktop.impl.portal.ScreenCast=wlr\norg.freedesktop.impl.portal.Screenshot=wlr\norg.freedesktop.impl.portal.FileChooser=gtk\n'
}

install_wallpaper() {
  run_cmd install -d -m 0755 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" "$LABWC_TARGET_HOME/.local/share/debian-labwc"
  run_cmd install -m 0644 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" "$SCRIPT_DIR/wallpaper/labwall2-1920x1080.png" "$LABWC_TARGET_HOME/.local/share/debian-labwc/labwall2-1920x1080.png"
}

render_all_configs() {
  local env_file="$1"
  local config_root="$LABWC_TARGET_HOME/.config"
  ensure_user_base_dirs
  run_cmd install -d -m 0755 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" \
    "$config_root/labwc" \
    "$config_root/waybar" \
    "$config_root/kanshi" \
    "$config_root/xfce4" \
    "$config_root/wofi" \
    "$config_root/mako" \
    "$config_root/swaylock" \
    "$config_root/foot" \
    "$config_root/gammastep" \
    "$config_root/xdg-desktop-portal" \
    "$config_root/debian-labwc" \
    "$config_root/systemd/user/gpg-agent.service.d" \
    "$config_root/systemd/user" \
    "$config_root"

  render_runtime_env "$env_file"
  render_home_dirs
  render_shell_startup_files
  render_xfce_helpers
  install_wallpaper
  render_labwc_environment
  render_labwc_rc_xml
  render_labwc_menu_xml
  render_labwc_autostart
  render_labwc_shutdown
  render_gpg_agent_override
  render_waybar_config
  render_waybar_style
  render_kanshi_config
  render_wofi
  render_mako
  render_swaylock
  render_foot
  render_gammastep
  render_portals
  run_cmd chown -R "$LABWC_TARGET_USER:$LABWC_TARGET_USER" "$LABWC_TARGET_HOME/.config" "$LABWC_TARGET_HOME/.local"
}
