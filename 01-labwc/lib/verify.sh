#!/usr/bin/env bash

package_is_installed() {
  dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null | grep -F "install ok installed" >/dev/null
}

expected_wallpaper_path_for_prefix() {
  local prefix="$1"
  local wallpaper_source_path=""
  wallpaper_source_path="$(
    find "$SCRIPT_DIR/wallpaper" -maxdepth 1 -type f -name "${prefix}-*" | LC_ALL=C sort | head -n 1
  )"
  if [[ -z "$wallpaper_source_path" ]]; then
    wallpaper_source_path="$(
      find "$SCRIPT_DIR/wallpaper" -maxdepth 1 -type f | LC_ALL=C sort | head -n 1
    )"
  fi
  [[ -n "$wallpaper_source_path" ]] || die "missing wallpaper asset under '$SCRIPT_DIR/wallpaper'"
  printf '%s/.local/share/debian-labwc/%s\n' "$LABWC_TARGET_HOME" "$(basename "$wallpaper_source_path")"
}

expected_background_wallpaper_path() {
  expected_wallpaper_path_for_prefix "wall"
}

expected_lock_wallpaper_path() {
  expected_wallpaper_path_for_prefix "lock"
}

verify_packages() {
  local pkg
  local -a package_list=()
  mapfile -t package_list < <(resolved_requested_packages)
  for pkg in "${package_list[@]}"; do
    package_is_installed "$pkg" || die "package '$pkg' is not installed"
  done
}

verify_paths() {
  require_file "/etc/greetd/config.toml"
  require_file "/etc/systemd/system/greetd.service.d/10-vt.conf"
  require_file "$SID_SOURCE_PATH"
  require_file "$SID_PREFERENCES_PATH"
  require_file "/usr/share/wayland-sessions/labwc.desktop"
  require_file "/usr/local/bin/debian-labwc-session"
  require_file "/usr/local/bin/debian-labwc-power-menu"
  require_file "/usr/local/bin/debian-labwc-screenshot-full"
  require_file "/usr/local/bin/debian-labwc-screenshot-region"
  require_file "/usr/local/bin/debian-labwc-record-toggle"
  require_file "/usr/local/bin/debian-labwc-refresh-outputs"
  require_file "/usr/local/bin/debian-labwc-lock"
  require_file "/usr/local/bin/debian-labwc-launcher-menu"
  require_file "/usr/local/bin/debian-labwc-module-menu"
  require_file "/usr/local/bin/debian-labwc-player-status"
  require_file "/usr/local/bin/debian-labwc-unlock-gpg-key"
  require_file "/usr/local/bin/debian-labwc-workspacectl"
  require_file "/usr/local/bin/debian-labwc-workspace-activate"
  require_file "/usr/local/bin/debian-labwc-workspace-send"
  require_file "/usr/local/bin/debian-labwc-workspace-state"
  require_file "/usr/local/bin/debian-labwc-workspace-status"
  require_file "/usr/bin/labwc-tweaks"
  require_file "/usr/share/applications/labwc_tweaks.desktop"
  require_file "/usr/share/metainfo/labwc_tweaks.appdata.xml"
  require_file "/usr/share/icons/hicolor/scalable/apps/labwc_tweaks.svg"
  require_file "$KEEPSECRET_BIN_PATH"
  require_file "$KEEPSECRET_DESKTOP_PATH"
  require_file "$KEEPSECRET_APPDATA_PATH"
  require_file "$KEEPSECRET_MANIFEST_PATH"
  require_file "$LABWC_TARGET_HOME/.config/labwc/rc.xml"
  require_file "$LABWC_TARGET_HOME/.config/labwc/menu.xml"
  require_file "$LABWC_TARGET_HOME/.config/labwc/autostart"
  require_file "$LABWC_TARGET_HOME/.config/labwc/environment"
  require_file "$LABWC_TARGET_HOME/.config/labwc/shutdown"
  require_file "$LABWC_TARGET_HOME/.config/waybar/config.jsonc"
  require_file "$LABWC_TARGET_HOME/.config/waybar/style.css"
  require_file "$LABWC_TARGET_HOME/.config/kanshi/config"
  require_file "$LABWC_TARGET_HOME/.config/xfce4/helpers.rc"
  require_file "$LABWC_TARGET_HOME/.config/kwalletrc"
  require_file "$LABWC_TARGET_HOME/.config/xdg-desktop-portal/portals.conf"
  require_file "$LABWC_TARGET_HOME/.config/starship.toml"
  require_file "$LABWC_TARGET_HOME/.gnupg/gpg-agent.conf"
  require_file "$LABWC_TARGET_HOME/.bashrc"
  require_file "$LABWC_TARGET_HOME/.profile"
  require_file "$LABWC_TARGET_HOME/.zshrc"
  require_file "$LABWC_TARGET_HOME/.zprofile"
  require_file "$LABWC_TARGET_HOME/.nanorc"
  require_file "$LABWC_TARGET_HOME/.tmux.conf"
  require_file "$LABWC_TARGET_HOME/.config/fzf/default-opts"
  require_file "$LABWC_TARGET_HOME/.config/fzf/preview.sh"
  require_file "$LABWC_TARGET_HOME/.config/systemd/user/gpg-agent.service.d/override.conf"
  require_file "$LABWC_TARGET_HOME/.config/systemd/user/xdg-desktop-portal.service.d/override.conf"
  require_file "$LABWC_TARGET_HOME/.config/systemd/user/xdg-desktop-portal-wlr.service.d/override.conf"
  require_file "$(expected_background_wallpaper_path)"
  require_file "$(expected_lock_wallpaper_path)"
  require_dir "$LABWC_TARGET_HOME/.local/state"
  require_dir "$LABWC_TARGET_HOME/Music"
  require_dir "$LABWC_TARGET_HOME/Videos"
  require_dir "$LABWC_TARGET_HOME/Documents"
}

verify_user_unit_enabled() {
  local unit_name="$1"
  local unit_path
  local install_target
  unit_path="$(resolve_user_unit_path "$unit_name")"
  while IFS= read -r install_target; do
    [[ -n "$install_target" ]] || continue
    require_file "$LABWC_TARGET_HOME/.config/systemd/user/${install_target}.wants/${unit_name}"
  done < <(unit_install_values "$unit_path" "WantedBy")
}

verify_services_enabled() {
  [[ "$(systemctl get-default)" == "graphical.target" ]] || die "default systemd target is not graphical.target"
  systemctl is-enabled greetd.service >/dev/null 2>&1 || die "greetd.service is not enabled"
  systemctl is-enabled seatd.service >/dev/null 2>&1 || die "seatd.service is not enabled"
  systemctl is-enabled NetworkManager.service >/dev/null 2>&1 || die "NetworkManager.service is not enabled"
  systemctl is-enabled udisks2.service >/dev/null 2>&1 || die "udisks2.service is not enabled"
  systemctl is-enabled upower.service >/dev/null 2>&1 || die "upower.service is not enabled"
}

verify_ownership() {
  local owner_group
  owner_group="$(stat -c '%U:%G' "$LABWC_TARGET_HOME/.config/labwc/rc.xml")"
  [[ "$owner_group" == "$LABWC_TARGET_USER:$LABWC_TARGET_USER" ]] || die "user config ownership is '$owner_group'"
}

verify_greeter_user() {
  getent passwd greeter >/dev/null 2>&1 || die "greeter user is missing"
}

verify_polkit_semantics() {
  local autostart_path="$LABWC_TARGET_HOME/.config/labwc/autostart"
  grep -F '/usr/lib/x86_64-linux-gnu/libexec/polkit-kde-authentication-agent-1 &' "$autostart_path" >/dev/null || die "labwc autostart missing KDE polkit auth agent"
  ! grep -F 'lxpolkit' "$autostart_path" >/dev/null || die "labwc autostart still references lxpolkit"
  grep -F '/usr/local/bin/debian-labwc-workspace-state 1' "$autostart_path" >/dev/null || die "labwc autostart missing initial workspace state sync"
  grep -F 'debian-labwc-unlock-gpg-key' "$autostart_path" >/dev/null || die "labwc autostart missing proactive GPG unlock helper"
  grep -F 'systemctl --user import-environment' "$autostart_path" >/dev/null || die "labwc autostart missing systemd user environment import"
  grep -F 'dbus-update-activation-environment --systemd "$@"' "$autostart_path" >/dev/null || die "labwc autostart missing D-Bus activation environment updates"
  ! grep -F 'is-active dbus.service' "$autostart_path" >/dev/null || die "labwc autostart still waits on dbus.service instead of the session bus socket"
}

verify_sid_repository_semantics() {
  grep -F "URIs: ${SID_REPO_URI}" "$SID_SOURCE_PATH" >/dev/null || die "sid source file missing ${SID_REPO_URI}"
  grep -F 'Suites: sid' "$SID_SOURCE_PATH" >/dev/null || die "sid source file missing sid suite"
  grep -F 'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg' "$SID_SOURCE_PATH" >/dev/null || die "sid source file missing Signed-By"
  grep -F 'Pin-Priority: 100' "$SID_PREFERENCES_PATH" >/dev/null || die "sid preferences missing pin priority 100"
}

verify_labwc_config_semantics() {
  local rc_path="$LABWC_TARGET_HOME/.config/labwc/rc.xml"
  grep -F '<action name="NextWindow" />' "$rc_path" >/dev/null || die "rc.xml missing explicit Alt+Tab next window action"
  grep -F '<action name="PreviousWindow" />' "$rc_path" >/dev/null || die "rc.xml missing explicit Alt+Tab previous window action"
  grep -F '<windowSwitcher preview="yes" outlines="yes" unshade="yes" order="focus">' "$rc_path" >/dev/null || die "rc.xml missing window switcher config"
  grep -F '<context name="Title">' "$rc_path" >/dev/null || die "rc.xml missing title mouse context"
  grep -F '<action name="ToggleMaximize" />' "$rc_path" >/dev/null || die "rc.xml missing titlebar double-click maximize"
  grep -F '<device category="default">' "$rc_path" >/dev/null || die "rc.xml missing default libinput profile"
  grep -F '<device category="touchpad">' "$rc_path" >/dev/null || die "rc.xml missing touchpad libinput profile"
  grep -F '<device category="non-touch">' "$rc_path" >/dev/null || die "rc.xml missing non-touch libinput profile"
  grep -F '<desktops>' "$rc_path" >/dev/null || die "rc.xml missing workspace configuration block"
  grep -F '<name>4</name>' "$rc_path" >/dev/null || die "rc.xml missing the fourth workspace name"
  grep -F "<naturalScroll>${LABWC_NATURAL_SCROLL}</naturalScroll>" "$rc_path" >/dev/null || die "rc.xml missing requested naturalScroll policy for default/touchpad"
  grep -F '<naturalScroll>no</naturalScroll>' "$rc_path" >/dev/null || die "rc.xml missing explicit non-touch naturalScroll disablement"
  grep -F '<keybind key="W-1">' "$rc_path" >/dev/null || die "rc.xml missing Super+1 workspace binding"
  grep -F '<action name="GoToDesktop" to="4" />' "$rc_path" >/dev/null || die "rc.xml missing workspace switch action for desktop 4"
  grep -F '<keybind key="W-S-1">' "$rc_path" >/dev/null || die "rc.xml missing Super+Shift+1 send-to-desktop binding"
  grep -F '<action name="SendToDesktop" to="4" follow="no" />' "$rc_path" >/dev/null || die "rc.xml missing send-to-desktop action for desktop 4"
  grep -F '<keybind key="W-t">' "$rc_path" >/dev/null || die "rc.xml missing Super+t terminal binding"
  grep -F '<command>foot</command>' "$rc_path" >/dev/null || die "rc.xml missing foot command binding"
  grep -F '<keybind key="W-b">' "$rc_path" >/dev/null || die "rc.xml missing Super+b browser binding"
  grep -F '<command>thorium-browser</command>' "$rc_path" >/dev/null || die "rc.xml missing thorium-browser command binding"
  grep -F '<keybind key="W-f">' "$rc_path" >/dev/null || die "rc.xml missing Super+f file manager binding"
  grep -F '<command>/usr/local/bin/debian-labwc-lock</command>' "$rc_path" >/dev/null || die "rc.xml missing dedicated lock helper binding"
  grep -F "XCURSOR_THEME=${LABWC_XCURSOR_THEME}" "$LABWC_TARGET_HOME/.config/labwc/environment" >/dev/null || die "labwc environment missing XCURSOR_THEME"
  grep -F "XCURSOR_SIZE=${LABWC_XCURSOR_SIZE}" "$LABWC_TARGET_HOME/.config/labwc/environment" >/dev/null || die "labwc environment missing XCURSOR_SIZE"
}

verify_greetd_semantics() {
  local greetd_config="/etc/greetd/config.toml"
  local greetd_dropin="/etc/systemd/system/greetd.service.d/10-vt.conf"
  local session_wrapper="/usr/local/bin/debian-labwc-session"
  grep -F "vt = ${LABWC_GREETD_VT}" "$greetd_config" >/dev/null || die "greetd config missing expected vt"
  grep -F 'switch = true' "$greetd_config" >/dev/null || die "greetd config missing explicit vt switch"
  grep -F 'tuigreet --time --asterisks --cmd /usr/local/bin/debian-labwc-session --sessions /usr/share/wayland-sessions' "$greetd_config" >/dev/null || die "greetd config missing expected tuigreet command"
  grep -F "Conflicts=getty@tty${LABWC_GREETD_VT}.service" "$greetd_dropin" >/dev/null || die "greetd drop-in missing getty conflict"
  grep -F "Before=getty@tty${LABWC_GREETD_VT}.service" "$greetd_dropin" >/dev/null || die "greetd drop-in missing getty ordering"
  grep -F 'export LABWC_UPDATE_ACTIVATION_ENV=1' "$session_wrapper" >/dev/null || die "labwc session wrapper missing explicit activation-environment enablement"
  grep -F 'export PASSWORD_STORE=kwallet6' "$session_wrapper" >/dev/null || die "session wrapper missing default KWallet password-store export"
  grep -F 'export ELECTRON_OZONE_PLATFORM_HINT=wayland' "$session_wrapper" >/dev/null || die "session wrapper missing Electron Wayland hint"
  grep -F 'export QT_QPA_PLATFORM=wayland' "$session_wrapper" >/dev/null || die "session wrapper missing Qt Wayland platform export"
  grep -F 'dbus-update-activation-environment --systemd "$@"' "$session_wrapper" >/dev/null || die "session wrapper missing D-Bus activation environment updates"
}

verify_waybar_config_semantics() {
  local waybar_path="$LABWC_TARGET_HOME/.config/waybar/config.jsonc"
  grep -F '"custom/launcher"' "$waybar_path" >/dev/null || die "waybar config missing launcher module"
  grep -F '"custom/workspace-1"' "$waybar_path" >/dev/null || die "waybar config missing workspace 1 module"
  grep -F '"custom/workspace-4"' "$waybar_path" >/dev/null || die "waybar config missing workspace 4 module"
  ! grep -F '"ext/workspaces"' "$waybar_path" >/dev/null || die "waybar config still references unsupported ext/workspaces"
  ! grep -F '"wlr/taskbar"' "$waybar_path" >/dev/null || die "waybar config still references unsupported wlr/taskbar"
  ! grep -F '"wlr/workspaces"' "$waybar_path" >/dev/null || die "waybar config still references unsupported wlr/workspaces"
  grep -F '"height": 42' "$waybar_path" >/dev/null || die "waybar config height is not set high enough for the configured modules"
  grep -F '"disk"' "$waybar_path" >/dev/null || die "waybar config missing disk module"
  grep -F '"signal": 10' "$waybar_path" >/dev/null || die "waybar workspace modules are not configured for signal-driven refresh"
  grep -F '"/usr/local/bin/debian-labwc-launcher-menu"' "$waybar_path" >/dev/null || die "waybar config missing launcher click binding"
  grep -F '"/usr/local/bin/debian-labwc-workspace-status 1"' "$waybar_path" >/dev/null || die "waybar config missing workspace status helper"
  grep -F '"/usr/local/bin/debian-labwc-workspace-activate 4"' "$waybar_path" >/dev/null || die "waybar config missing workspace activation helper"
  ! grep -F '"on-click-right": "/usr/local/bin/debian-labwc-workspace-send' "$waybar_path" >/dev/null || die "waybar config still exposes the broken workspace send action"
  grep -F '"/usr/local/bin/debian-labwc-module-menu network menu"' "$waybar_path" >/dev/null || die "waybar config missing network right-click menu"
  grep -F '"/usr/local/bin/debian-labwc-module-menu storage menu"' "$waybar_path" >/dev/null || die "waybar config missing storage right-click menu"
  grep -F '"/usr/local/bin/debian-labwc-player-status"' "$waybar_path" >/dev/null || die "waybar config missing player status helper"
  grep -F '"tooltip-format": "<tt><small>{calendar}</small></tt>"' "$waybar_path" >/dev/null || die "waybar clock tooltip is not configured to show the calendar"
  grep -F '"on-click": "gsimplecal"' "$waybar_path" >/dev/null || die "waybar clock is not configured to launch gsimplecal on click"
  grep -F '"calendar": {' "$waybar_path" >/dev/null || die "waybar clock calendar block is missing"
}

verify_thunar_terminal_semantics() {
  grep -F 'TerminalEmulator=foot' "$LABWC_TARGET_HOME/.config/xfce4/helpers.rc" >/dev/null || die "xfce helpers missing foot terminal mapping"
}

verify_labwc_tweaks_semantics() {
  grep -F 'Exec=labwc-tweaks' /usr/share/applications/labwc_tweaks.desktop >/dev/null || die "labwc-tweaks desktop file missing expected Exec"
}

verify_swaylock_semantics() {
  local swaylock_path="$LABWC_TARGET_HOME/.config/swaylock/config"
  local lock_helper="/usr/local/bin/debian-labwc-lock"
  local wallpaper_path
  wallpaper_path="$(expected_lock_wallpaper_path)"
  grep -F "image=${wallpaper_path}" "$swaylock_path" >/dev/null || die "swaylock config is not using the installed wallpaper asset"
  grep -F "scaling=${LABWC_WALLPAPER_MODE}" "$swaylock_path" >/dev/null || die "swaylock config is not using the configured wallpaper mode"
  grep -F 'show-failed-attempts' "$swaylock_path" >/dev/null || die "swaylock config is missing failed-attempt feedback"
  grep -F -- '--image "$wallpaper_path"' "$lock_helper" >/dev/null || die "lock helper is not passing the wallpaper explicitly"
  grep -F -- '--config "$config_path"' "$lock_helper" >/dev/null || die "lock helper is not using the generated swaylock config"
  grep -F 'exec /usr/local/bin/debian-labwc-lock' "$SCRIPT_DIR/bin/power-menu.sh" >/dev/null || die "power menu is not using the dedicated lock helper"
}

verify_gpg_agent_semantics() {
  local shutdown_path="$LABWC_TARGET_HOME/.config/labwc/shutdown"
  local override_path="$LABWC_TARGET_HOME/.config/systemd/user/gpg-agent.service.d/override.conf"
  local portal_override_path="$LABWC_TARGET_HOME/.config/systemd/user/xdg-desktop-portal.service.d/override.conf"
  local portal_wlr_override_path="$LABWC_TARGET_HOME/.config/systemd/user/xdg-desktop-portal-wlr.service.d/override.conf"
  local session_wrapper="/usr/local/bin/debian-labwc-session"
  local gpg_agent_config="$LABWC_TARGET_HOME/.gnupg/gpg-agent.conf"
  grep -F 'pkill -x "waybar"' "$shutdown_path" >/dev/null || die "labwc shutdown hook missing waybar stop"
  grep -F 'gpgconf --kill gpg-agent' "$shutdown_path" >/dev/null || die "labwc shutdown hook missing gpg-agent kill"
  grep -F 'pkill -x "polkit-kde-authentication-agent-1"' "$shutdown_path" >/dev/null || die "labwc shutdown hook missing KDE polkit agent stop"
  grep -F 'xdg-desktop-portal.service' "$shutdown_path" >/dev/null || die "labwc shutdown hook missing portal stop"
  grep -F 'xdg-desktop-portal-wlr.service' "$shutdown_path" >/dev/null || die "labwc shutdown hook missing portal-wlr stop"
  grep -F 'systemctl --user stop \' "$shutdown_path" >/dev/null || die "labwc shutdown hook missing explicit pipewire shutdown"
  grep -F 'wireplumber.service' "$shutdown_path" >/dev/null || die "labwc shutdown hook missing wireplumber stop"
  grep -F 'After=pipewire.service wireplumber.service xdg-desktop-portal-wlr.service' "$portal_override_path" >/dev/null || die "portal override missing PipeWire ordering"
  grep -F 'After=pipewire.service wireplumber.service' "$portal_wlr_override_path" >/dev/null || die "portal-wlr override missing PipeWire ordering"
  grep -F 'BindsTo=pipewire.service' "$portal_wlr_override_path" >/dev/null || die "portal-wlr override missing PipeWire binding"
  grep -F 'TimeoutStopSec=10s' "$override_path" >/dev/null || die "gpg-agent override missing reduced stop timeout"
  grep -F 'enable-ssh-support' "$gpg_agent_config" >/dev/null || die "gpg-agent config missing ssh agent support"
  grep -F 'pinentry-program /usr/bin/pinentry-gtk-2' "$gpg_agent_config" >/dev/null || die "gpg-agent config missing explicit pinentry"
  grep -F 'disable-scdaemon' "$gpg_agent_config" >/dev/null || die "gpg-agent config missing scdaemon disablement"
  grep -F 'no-allow-external-cache' "$gpg_agent_config" >/dev/null || die "gpg-agent config missing KWallet external cache disablement"
  grep -F "default-cache-ttl ${KWALLET_SESSION_GPG_CACHE_TTL_SEC}" "$gpg_agent_config" >/dev/null || die "gpg-agent config missing configured cache ttl"
  grep -F "max-cache-ttl ${KWALLET_SESSION_GPG_CACHE_TTL_SEC}" "$gpg_agent_config" >/dev/null || die "gpg-agent config missing configured max cache ttl"
  grep -F "default-cache-ttl-ssh ${KWALLET_SESSION_GPG_CACHE_TTL_SEC}" "$gpg_agent_config" >/dev/null || die "gpg-agent config missing configured ssh cache ttl"
  grep -F "max-cache-ttl-ssh ${KWALLET_SESSION_GPG_CACHE_TTL_SEC}" "$gpg_agent_config" >/dev/null || die "gpg-agent config missing configured ssh max cache ttl"
  grep -F 'gpgconf --launch gpg-agent' "$session_wrapper" >/dev/null || die "session wrapper missing gpg-agent launch"
  grep -F 'export SSH_AUTH_SOCK=' "$session_wrapper" >/dev/null || die "session wrapper missing SSH_AUTH_SOCK export"
}

verify_kwallet_semantics() {
  local kwallet_config="$LABWC_TARGET_HOME/.config/kwalletrc"
  local portals_path="$LABWC_TARGET_HOME/.config/xdg-desktop-portal/portals.conf"
  grep -F '[Wallet]' "$kwallet_config" >/dev/null || die "kwalletrc missing Wallet section"
  grep -F 'Enabled=true' "$kwallet_config" >/dev/null || die "kwalletrc does not enable KWallet"
  grep -F '[org.freedesktop.secrets]' "$kwallet_config" >/dev/null || die "kwalletrc missing Secret Service section"
  grep -F 'apiEnabled=true' "$kwallet_config" >/dev/null || die "kwalletrc does not enable Secret Service compatibility"
  grep -F 'org.freedesktop.impl.portal.Secret=kwallet' "$portals_path" >/dev/null || die "portals.conf does not force the KWallet Secret portal"
}

verify_keepsecret_semantics() {
  grep -Fx "$KEEPSECRET_BIN_PATH" "$KEEPSECRET_MANIFEST_PATH" >/dev/null || die "keepsecret install manifest is missing the binary path"
  grep -Fx "$KEEPSECRET_DESKTOP_PATH" "$KEEPSECRET_MANIFEST_PATH" >/dev/null || die "keepsecret install manifest is missing the desktop path"
  grep -Fx "$KEEPSECRET_APPDATA_PATH" "$KEEPSECRET_MANIFEST_PATH" >/dev/null || die "keepsecret install manifest is missing the metainfo path"
  while IFS= read -r installed_path; do
    [[ -n "$installed_path" ]] || continue
    require_file "$installed_path"
  done <"$KEEPSECRET_MANIFEST_PATH"
  grep -F 'Exec=keepsecret' "$KEEPSECRET_DESKTOP_PATH" >/dev/null || die "keepsecret desktop file missing keepsecret Exec"
}

verify_foot_semantics() {
  local foot_path="$LABWC_TARGET_HOME/.config/foot/foot.ini"
  grep -F '[colors-dark]' "$foot_path" >/dev/null || die "foot config is missing the non-deprecated [colors-dark] section"
  ! grep -F '[colors]' "$foot_path" >/dev/null || die "foot config still uses deprecated [colors] section"
}

verify_shell_config_semantics() {
  grep -F 'umask 022' "$LABWC_TARGET_HOME/.bashrc" >/dev/null || die ".bashrc missing umask"
  grep -F "/data/usr/local/bin:/usr/local/bin:\$HOME/.local/bin:\$PATH" "$LABWC_TARGET_HOME/.bashrc" >/dev/null || die ".bashrc missing PATH additions"
  grep -F 'export EDITOR=nano' "$LABWC_TARGET_HOME/.bashrc" >/dev/null || die ".bashrc missing EDITOR=nano"
  grep -F 'export VISUAL=nano' "$LABWC_TARGET_HOME/.bashrc" >/dev/null || die ".bashrc missing VISUAL=nano"
  grep -F "alias ll='ls -alFh'" "$LABWC_TARGET_HOME/.bashrc" >/dev/null || die ".bashrc missing ll alias"
  grep -F "alias la='ls -A'" "$LABWC_TARGET_HOME/.bashrc" >/dev/null || die ".bashrc missing la alias"
  grep -F 'export HISTSIZE=10000' "$LABWC_TARGET_HOME/.bashrc" >/dev/null || die ".bashrc missing HISTSIZE"
  grep -F 'export HISTFILESIZE=20000' "$LABWC_TARGET_HOME/.bashrc" >/dev/null || die ".bashrc missing HISTFILESIZE"
  grep -F 'bash_completion' "$LABWC_TARGET_HOME/.bashrc" >/dev/null || die ".bashrc missing bash completion setup"
  grep -F "alias fd='fdfind'" "$LABWC_TARGET_HOME/.bashrc" >/dev/null || die ".bashrc missing fd alias for fdfind"
  grep -F "export FZF_DEFAULT_COMMAND='fdfind --hidden --follow --exclude .git .'" "$LABWC_TARGET_HOME/.bashrc" >/dev/null || die ".bashrc missing fzf fd default command"
  grep -F 'export FZF_DEFAULT_OPTS_FILE="$HOME/.config/fzf/default-opts"' "$LABWC_TARGET_HOME/.bashrc" >/dev/null || die ".bashrc missing fzf opts file"
  grep -F '/usr/share/doc/fzf/examples/key-bindings.bash' "$LABWC_TARGET_HOME/.bashrc" >/dev/null || die ".bashrc missing fzf key bindings"
  grep -F '/usr/share/doc/fzf/examples/completion.bash' "$LABWC_TARGET_HOME/.bashrc" >/dev/null || die ".bashrc missing fzf completion"
  grep -F '_fzf_compgen_path()' "$LABWC_TARGET_HOME/.bashrc" >/dev/null || die ".bashrc missing custom fzf path generator"
  grep -F 'command fdfind --hidden --follow --exclude .git .' "$LABWC_TARGET_HOME/.bashrc" >/dev/null || die ".bashrc missing fdfind-backed fzf generator"
  grep -F 'starship init bash' "$LABWC_TARGET_HOME/.bashrc" >/dev/null || die ".bashrc missing starship init"
  grep -F 'umask 022' "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing umask"
  grep -F "/data/usr/local/bin:/usr/local/bin:\$HOME/.local/bin:\$PATH" "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing PATH additions"
  grep -F 'export EDITOR=nano' "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing EDITOR=nano"
  grep -F 'export VISUAL=nano' "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing VISUAL=nano"
  grep -F "alias ll='ls -alFh'" "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing ll alias"
  grep -F "alias la='ls -A'" "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing la alias"
  grep -F 'export HISTSIZE=10000' "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing HISTSIZE"
  grep -F 'export HISTFILESIZE=20000' "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing HISTFILESIZE"
  grep -F 'SAVEHIST="${HISTFILESIZE}"' "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing SAVEHIST alignment"
  grep -F 'compinit' "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing compinit"
  grep -F 'zsh-autosuggestions' "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing zsh-autosuggestions setup"
  grep -F "alias fd='fdfind'" "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing fd alias for fdfind"
  grep -F "export FZF_DEFAULT_COMMAND='fdfind --hidden --follow --exclude .git .'" "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing fzf fd default command"
  grep -F 'export FZF_DEFAULT_OPTS_FILE="$HOME/.config/fzf/default-opts"' "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing fzf opts file"
  grep -F '/usr/share/doc/fzf/examples/key-bindings.zsh' "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing fzf key bindings"
  grep -F '/usr/share/doc/fzf/examples/completion.zsh' "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing fzf completion"
  grep -F '_fzf_compgen_path()' "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing custom fzf path generator"
  grep -F 'command fdfind --type d --hidden --follow --exclude .git .' "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing fdfind-backed directory generator"
  grep -F 'starship init zsh' "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing starship init"
  grep -F '[ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ]' "$LABWC_TARGET_HOME/.profile" >/dev/null || die ".profile missing bash-only guard for .bashrc"
  grep -F '. "$HOME/.bashrc"' "$LABWC_TARGET_HOME/.profile" >/dev/null || die ".profile missing POSIX .bashrc source form"
  grep -F 'if [ -f "$HOME/.profile" ]; then' "$LABWC_TARGET_HOME/.zprofile" >/dev/null || die ".zprofile missing POSIX-safe .profile guard"
  grep -F '. "$HOME/.profile"' "$LABWC_TARGET_HOME/.zprofile" >/dev/null || die ".zprofile missing POSIX-safe .profile source form"
  grep -F 'set mouse' "$LABWC_TARGET_HOME/.nanorc" >/dev/null || die ".nanorc missing mouse support"
  grep -F 'set autoindent' "$LABWC_TARGET_HOME/.nanorc" >/dev/null || die ".nanorc missing autoindent"
  grep -F 'set tabsize 4' "$LABWC_TARGET_HOME/.nanorc" >/dev/null || die ".nanorc missing tabsize"
  grep -F 'set tabstospaces' "$LABWC_TARGET_HOME/.nanorc" >/dev/null || die ".nanorc missing tabstospaces"
  grep -F 'set softwrap' "$LABWC_TARGET_HOME/.nanorc" >/dev/null || die ".nanorc missing softwrap"
  grep -F 'set indicator' "$LABWC_TARGET_HOME/.nanorc" >/dev/null || die ".nanorc missing indicator"
  grep -F 'set titlecolor bold,white,blue' "$LABWC_TARGET_HOME/.nanorc" >/dev/null || die ".nanorc missing titlecolor"
  grep -F 'set numbercolor cyan' "$LABWC_TARGET_HOME/.nanorc" >/dev/null || die ".nanorc missing numbercolor"
  grep -F 'set keycolor cyan' "$LABWC_TARGET_HOME/.nanorc" >/dev/null || die ".nanorc missing keycolor"
  grep -F 'set functioncolor green' "$LABWC_TARGET_HOME/.nanorc" >/dev/null || die ".nanorc missing functioncolor"
  grep -F 'include "/usr/share/nano/*.nanorc"' "$LABWC_TARGET_HOME/.nanorc" >/dev/null || die ".nanorc missing syntax include"
  grep -F 'format = "$username$hostname$directory$git_branch$git_status\n$character "' "$LABWC_TARGET_HOME/.config/starship.toml" >/dev/null || die "starship.toml missing multiline prompt format"
  grep -F '[username]' "$LABWC_TARGET_HOME/.config/starship.toml" >/dev/null || die "starship.toml missing username config"
  grep -F '[hostname]' "$LABWC_TARGET_HOME/.config/starship.toml" >/dev/null || die "starship.toml missing hostname config"
  grep -F '[directory]' "$LABWC_TARGET_HOME/.config/starship.toml" >/dev/null || die "starship.toml missing directory config"
  grep -F '[git_branch]' "$LABWC_TARGET_HOME/.config/starship.toml" >/dev/null || die "starship.toml missing git_branch config"
  grep -F '[git_status]' "$LABWC_TARGET_HOME/.config/starship.toml" >/dev/null || die "starship.toml missing git_status config"
  grep -F -- '--layout=reverse' "$LABWC_TARGET_HOME/.config/fzf/default-opts" >/dev/null || die "fzf default opts missing layout"
  grep -F -- '--bind=ctrl-/:toggle-preview' "$LABWC_TARGET_HOME/.config/fzf/default-opts" >/dev/null || die "fzf default opts missing preview toggle"
  grep -F -- '--color=bg:#0f1720' "$LABWC_TARGET_HOME/.config/fzf/default-opts" >/dev/null || die "fzf default opts missing color theme"
  grep -F 'ls -la --color=always --group-directories-first -- "$target"' "$LABWC_TARGET_HOME/.config/fzf/preview.sh" >/dev/null || die "fzf preview helper missing directory listing"
  grep -F 'nl -ba -- "$target" | sed -n' "$LABWC_TARGET_HOME/.config/fzf/preview.sh" >/dev/null || die "fzf preview helper missing text preview"
}

verify_tmux_semantics() {
  local tmux_path="$LABWC_TARGET_HOME/.tmux.conf"
  grep -F 'set -g default-terminal "tmux-256color"' "$tmux_path" >/dev/null || die ".tmux.conf missing tmux-256color terminal"
  grep -F 'set -as terminal-features ",foot*:RGB,ccolour,cstyle,extkeys,focus,title,clipboard"' "$tmux_path" >/dev/null || die ".tmux.conf missing foot terminal features"
  grep -F 'set -g focus-events on' "$tmux_path" >/dev/null || die ".tmux.conf missing focus events"
  grep -F 'set -g mouse on' "$tmux_path" >/dev/null || die ".tmux.conf missing mouse mode"
  grep -F 'set -g history-limit 100000' "$tmux_path" >/dev/null || die ".tmux.conf missing expanded history"
  grep -F 'bind c new-window -c "#{pane_current_path}"' "$tmux_path" >/dev/null || die ".tmux.conf missing current-path new-window binding"
  grep -F 'copy-pipe-and-cancel "wl-copy"' "$tmux_path" >/dev/null || die ".tmux.conf missing wl-copy copy-mode integration"
}

verify_mako_semantics() {
  local mako_path="$LABWC_TARGET_HOME/.config/mako/config"
  grep -F 'width=420' "$mako_path" >/dev/null || die "mako config missing notification width"
  grep -F 'border-radius=14' "$mako_path" >/dev/null || die "mako config missing rounded corners"
  grep -F 'max-history=100' "$mako_path" >/dev/null || die "mako config missing expanded history"
  grep -F 'group-by=summary,app-name,urgency' "$mako_path" >/dev/null || die "mako config missing grouping policy"
  grep -F 'hidden-format=<b>%h hidden</b> (%t total)' "$mako_path" >/dev/null || die "mako config missing hidden notification format"
  grep -F '[urgency=critical]' "$mako_path" >/dev/null || die "mako config missing critical urgency section"
  grep -F '[mode=do-not-disturb]' "$mako_path" >/dev/null || die "mako config missing do-not-disturb mode"
}

verify_install() {
  verify_packages
  verify_paths
  verify_user_unit_enabled pipewire.socket
  verify_user_unit_enabled pipewire-pulse.socket
  verify_user_unit_enabled wireplumber.service
  verify_services_enabled
  verify_greeter_user
  verify_polkit_semantics
  verify_sid_repository_semantics
  verify_ownership
  verify_greetd_semantics
  verify_labwc_config_semantics
  verify_waybar_config_semantics
  verify_thunar_terminal_semantics
  verify_labwc_tweaks_semantics
  verify_swaylock_semantics
  verify_gpg_agent_semantics
  verify_kwallet_semantics
  verify_keepsecret_semantics
  verify_foot_semantics
  verify_shell_config_semantics
  verify_tmux_semantics
  verify_mako_semantics
  log_info "verification completed"
}
