#!/usr/bin/env bash

package_is_installed() {
  dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null | grep -F "install ok installed" >/dev/null
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
  require_file "/etc/tmpfiles.d/debian-labwc-polkit.conf"
  require_file "/usr/share/wayland-sessions/labwc.desktop"
  require_file "/usr/local/bin/debian-labwc-session"
  require_file "/usr/local/bin/debian-labwc-power-menu"
  require_file "/usr/local/bin/debian-labwc-screenshot-full"
  require_file "/usr/local/bin/debian-labwc-screenshot-region"
  require_file "/usr/local/bin/debian-labwc-record-toggle"
  require_file "/usr/local/bin/debian-labwc-refresh-outputs"
  require_file "/usr/local/bin/debian-labwc-launcher-menu"
  require_file "/usr/local/bin/debian-labwc-module-menu"
  require_file "/usr/local/bin/debian-labwc-player-status"
  require_file "/usr/bin/labwc-tweaks"
  require_file "/usr/share/applications/labwc_tweaks.desktop"
  require_file "/usr/share/metainfo/labwc_tweaks.appdata.xml"
  require_file "/usr/share/icons/hicolor/scalable/apps/labwc_tweaks.svg"
  require_file "$LABWC_TARGET_HOME/.config/labwc/rc.xml"
  require_file "$LABWC_TARGET_HOME/.config/labwc/menu.xml"
  require_file "$LABWC_TARGET_HOME/.config/labwc/autostart"
  require_file "$LABWC_TARGET_HOME/.config/labwc/environment"
  require_file "$LABWC_TARGET_HOME/.config/labwc/shutdown"
  require_file "$LABWC_TARGET_HOME/.config/waybar/config.jsonc"
  require_file "$LABWC_TARGET_HOME/.config/kanshi/config"
  require_file "$LABWC_TARGET_HOME/.config/xfce4/helpers.rc"
  require_file "$LABWC_TARGET_HOME/.config/xdg-desktop-portal/portals.conf"
  require_dir "/usr/local/share/polkit-1/rules.d"
  require_file "$LABWC_TARGET_HOME/.config/debian-labwc/runtime.env"
  require_file "$LABWC_TARGET_HOME/.config/starship.toml"
  require_file "$LABWC_TARGET_HOME/.gnupg/gpg-agent.conf"
  require_file "$LABWC_TARGET_HOME/.bashrc"
  require_file "$LABWC_TARGET_HOME/.profile"
  require_file "$LABWC_TARGET_HOME/.zshrc"
  require_file "$LABWC_TARGET_HOME/.zprofile"
  require_file "$LABWC_TARGET_HOME/.config/systemd/user/gpg-agent.service.d/override.conf"
  require_file "$LABWC_TARGET_HOME/.local/share/debian-labwc/labwall2-1920x1080.png"
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
}

verify_ownership() {
  local owner_group
  owner_group="$(stat -c '%U:%G' "$LABWC_TARGET_HOME/.config/labwc/rc.xml")"
  [[ "$owner_group" == "$LABWC_TARGET_USER:$LABWC_TARGET_USER" ]] || die "user config ownership is '$owner_group'"
}

verify_greeter_user() {
  getent passwd greeter >/dev/null 2>&1 || die "greeter user is missing"
}

verify_polkitd_user() {
  getent group polkitd >/dev/null 2>&1 || die "polkitd group is missing"
  getent passwd polkitd >/dev/null 2>&1 || die "polkitd user is missing"
}

verify_polkit_semantics() {
  local autostart_path="$LABWC_TARGET_HOME/.config/labwc/autostart"
  grep -F 'd /run/polkit-1/rules.d 0755 root root -' /etc/tmpfiles.d/debian-labwc-polkit.conf >/dev/null || die "polkit tmpfiles config missing runtime rules directory"
  grep -F 'lxpolkit &' "$autostart_path" >/dev/null || die "labwc autostart missing lxpolkit auth agent"
  grep -F 'systemctl --user import-environment' "$autostart_path" >/dev/null || die "labwc autostart missing systemd user environment import"
  ! grep -F 'is-active dbus.service' "$autostart_path" >/dev/null || die "labwc autostart still waits on dbus.service instead of the session bus socket"
}

verify_labwc_config_semantics() {
  local rc_path="$LABWC_TARGET_HOME/.config/labwc/rc.xml"
  grep -F '<action name="NextWindow" />' "$rc_path" >/dev/null || die "rc.xml missing explicit Alt+Tab next window action"
  grep -F '<action name="PreviousWindow" />' "$rc_path" >/dev/null || die "rc.xml missing explicit Alt+Tab previous window action"
  grep -F '<windowSwitcher preview="yes" outlines="yes" unshade="yes" order="focus">' "$rc_path" >/dev/null || die "rc.xml missing window switcher config"
  grep -F '<context name="Title">' "$rc_path" >/dev/null || die "rc.xml missing title mouse context"
  grep -F '<action name="ToggleMaximize" />' "$rc_path" >/dev/null || die "rc.xml missing titlebar double-click maximize"
  grep -F '<device category="touchpad">' "$rc_path" >/dev/null || die "rc.xml missing touchpad libinput profile"
  grep -F '<device category="non-touch">' "$rc_path" >/dev/null || die "rc.xml missing non-touch libinput profile"
  grep -F "<naturalScroll>${LABWC_NATURAL_SCROLL}</naturalScroll>" "$rc_path" >/dev/null || die "rc.xml missing requested naturalScroll policy"
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
}

verify_waybar_config_semantics() {
  local waybar_path="$LABWC_TARGET_HOME/.config/waybar/config.jsonc"
  grep -F '"custom/launcher"' "$waybar_path" >/dev/null || die "waybar config missing launcher module"
  ! grep -F '"ext/workspaces"' "$waybar_path" >/dev/null || die "waybar config still references unsupported ext/workspaces"
  ! grep -F '"wlr/taskbar"' "$waybar_path" >/dev/null || die "waybar config still references unsupported wlr/taskbar"
  ! grep -F '"wlr/workspaces"' "$waybar_path" >/dev/null || die "waybar config still references unsupported wlr/workspaces"
  grep -F '"height": 42' "$waybar_path" >/dev/null || die "waybar config height is not set high enough for the configured modules"
  grep -F '"disk"' "$waybar_path" >/dev/null || die "waybar config missing disk module"
  grep -F '"/usr/local/bin/debian-labwc-launcher-menu"' "$waybar_path" >/dev/null || die "waybar config missing launcher click binding"
  grep -F '"/usr/local/bin/debian-labwc-module-menu network menu"' "$waybar_path" >/dev/null || die "waybar config missing network right-click menu"
  grep -F '"/usr/local/bin/debian-labwc-module-menu storage menu"' "$waybar_path" >/dev/null || die "waybar config missing storage right-click menu"
  grep -F '"/usr/local/bin/debian-labwc-player-status"' "$waybar_path" >/dev/null || die "waybar config missing player status helper"
}

verify_thunar_terminal_semantics() {
  grep -F 'TerminalEmulator=foot' "$LABWC_TARGET_HOME/.config/xfce4/helpers.rc" >/dev/null || die "xfce helpers missing foot terminal mapping"
}

verify_labwc_tweaks_semantics() {
  grep -F 'Exec=labwc-tweaks' /usr/share/applications/labwc_tweaks.desktop >/dev/null || die "labwc-tweaks desktop file missing expected Exec"
}

verify_gpg_agent_semantics() {
  local shutdown_path="$LABWC_TARGET_HOME/.config/labwc/shutdown"
  local override_path="$LABWC_TARGET_HOME/.config/systemd/user/gpg-agent.service.d/override.conf"
  local session_wrapper="/usr/local/bin/debian-labwc-session"
  local gpg_agent_config="$LABWC_TARGET_HOME/.gnupg/gpg-agent.conf"
  grep -F 'pkill -x "waybar"' "$shutdown_path" >/dev/null || die "labwc shutdown hook missing waybar stop"
  grep -F 'gpgconf --kill gpg-agent' "$shutdown_path" >/dev/null || die "labwc shutdown hook missing gpg-agent kill"
  grep -F 'TimeoutStopSec=10s' "$override_path" >/dev/null || die "gpg-agent override missing reduced stop timeout"
  grep -F 'enable-ssh-support' "$gpg_agent_config" >/dev/null || die "gpg-agent config missing ssh agent support"
  grep -F 'gpgconf --launch gpg-agent' "$session_wrapper" >/dev/null || die "session wrapper missing gpg-agent launch"
  grep -F 'export SSH_AUTH_SOCK=' "$session_wrapper" >/dev/null || die "session wrapper missing SSH_AUTH_SOCK export"
}

verify_shell_config_semantics() {
  grep -F 'umask 022' "$LABWC_TARGET_HOME/.bashrc" >/dev/null || die ".bashrc missing umask"
  grep -F "/data/usr/local/bin:/usr/local/bin:\$HOME/.local/bin:\$PATH" "$LABWC_TARGET_HOME/.bashrc" >/dev/null || die ".bashrc missing PATH additions"
  grep -F 'bash_completion' "$LABWC_TARGET_HOME/.bashrc" >/dev/null || die ".bashrc missing bash completion setup"
  grep -F 'starship init bash' "$LABWC_TARGET_HOME/.bashrc" >/dev/null || die ".bashrc missing starship init"
  grep -F 'umask 022' "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing umask"
  grep -F "/data/usr/local/bin:/usr/local/bin:\$HOME/.local/bin:\$PATH" "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing PATH additions"
  grep -F 'compinit' "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing compinit"
  grep -F 'zsh-autosuggestions' "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing zsh-autosuggestions setup"
  grep -F 'starship init zsh' "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing starship init"
  grep -F '[ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ]' "$LABWC_TARGET_HOME/.profile" >/dev/null || die ".profile missing bash-only guard for .bashrc"
  grep -F '. "$HOME/.bashrc"' "$LABWC_TARGET_HOME/.profile" >/dev/null || die ".profile missing POSIX .bashrc source form"
  grep -F 'if [ -f "$HOME/.profile" ]; then' "$LABWC_TARGET_HOME/.zprofile" >/dev/null || die ".zprofile missing POSIX-safe .profile guard"
  grep -F '. "$HOME/.profile"' "$LABWC_TARGET_HOME/.zprofile" >/dev/null || die ".zprofile missing POSIX-safe .profile source form"
  grep -F 'format = "$username$hostname$directory$git_branch$git_status\n$character "' "$LABWC_TARGET_HOME/.config/starship.toml" >/dev/null || die "starship.toml missing multiline prompt format"
  grep -F '[username]' "$LABWC_TARGET_HOME/.config/starship.toml" >/dev/null || die "starship.toml missing username config"
  grep -F '[hostname]' "$LABWC_TARGET_HOME/.config/starship.toml" >/dev/null || die "starship.toml missing hostname config"
  grep -F '[directory]' "$LABWC_TARGET_HOME/.config/starship.toml" >/dev/null || die "starship.toml missing directory config"
  grep -F '[git_branch]' "$LABWC_TARGET_HOME/.config/starship.toml" >/dev/null || die "starship.toml missing git_branch config"
  grep -F '[git_status]' "$LABWC_TARGET_HOME/.config/starship.toml" >/dev/null || die "starship.toml missing git_status config"
}

verify_install() {
  verify_packages
  verify_paths
  verify_user_unit_enabled pipewire.socket
  verify_user_unit_enabled pipewire-pulse.socket
  verify_user_unit_enabled wireplumber.service
  verify_services_enabled
  verify_greeter_user
  verify_polkitd_user
  verify_polkit_semantics
  verify_ownership
  verify_greetd_semantics
  verify_labwc_config_semantics
  verify_waybar_config_semantics
  verify_thunar_terminal_semantics
  verify_labwc_tweaks_semantics
  verify_gpg_agent_semantics
  verify_shell_config_semantics
  log_info "verification completed"
}
