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
  require_file "/usr/share/wayland-sessions/labwc.desktop"
  require_file "/usr/local/bin/debian-labwc-session"
  require_file "/usr/local/bin/debian-labwc-power-menu"
  require_file "/usr/local/bin/debian-labwc-screenshot-full"
  require_file "/usr/local/bin/debian-labwc-screenshot-region"
  require_file "/usr/local/bin/debian-labwc-record-toggle"
  require_file "/usr/local/bin/debian-labwc-refresh-outputs"
  require_file "$LABWC_TARGET_HOME/.config/labwc/rc.xml"
  require_file "$LABWC_TARGET_HOME/.config/labwc/menu.xml"
  require_file "$LABWC_TARGET_HOME/.config/labwc/autostart"
  require_file "$LABWC_TARGET_HOME/.config/waybar/config.jsonc"
  require_file "$LABWC_TARGET_HOME/.config/kanshi/config"
  require_file "$LABWC_TARGET_HOME/.config/xdg-desktop-portal/portals.conf"
  require_file "$LABWC_TARGET_HOME/.config/debian-labwc/runtime.env"
  require_file "$LABWC_TARGET_HOME/.config/starship.toml"
  require_file "$LABWC_TARGET_HOME/.bashrc"
  require_file "$LABWC_TARGET_HOME/.profile"
  require_file "$LABWC_TARGET_HOME/.zshrc"
  require_file "$LABWC_TARGET_HOME/.zprofile"
  require_file "$LABWC_TARGET_HOME/.config/systemd/user/default.target.wants/pipewire.service"
  require_file "$LABWC_TARGET_HOME/.config/systemd/user/default.target.wants/pipewire.socket"
  require_file "$LABWC_TARGET_HOME/.config/systemd/user/default.target.wants/pipewire-pulse.service"
  require_file "$LABWC_TARGET_HOME/.config/systemd/user/default.target.wants/pipewire-pulse.socket"
  require_file "$LABWC_TARGET_HOME/.config/systemd/user/default.target.wants/wireplumber.service"
  require_file "$LABWC_TARGET_HOME/.local/share/debian-labwc/labwall2-1920x1080.png"
  require_dir "$LABWC_TARGET_HOME/Music"
  require_dir "$LABWC_TARGET_HOME/Videos"
  require_dir "$LABWC_TARGET_HOME/Documents"
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

verify_labwc_config_semantics() {
  local rc_path="$LABWC_TARGET_HOME/.config/labwc/rc.xml"
  grep -F '<action name="NextWindow" />' "$rc_path" >/dev/null || die "rc.xml missing explicit Alt+Tab next window action"
  grep -F '<action name="PreviousWindow" />' "$rc_path" >/dev/null || die "rc.xml missing explicit Alt+Tab previous window action"
  grep -F '<windowSwitcher preview="yes" outlines="yes" unshade="yes" order="focus">' "$rc_path" >/dev/null || die "rc.xml missing window switcher config"
  grep -F '<context name="Title">' "$rc_path" >/dev/null || die "rc.xml missing title mouse context"
  grep -F '<action name="ToggleMaximize" />' "$rc_path" >/dev/null || die "rc.xml missing titlebar double-click maximize"
}

verify_shell_config_semantics() {
  grep -F 'bash_completion' "$LABWC_TARGET_HOME/.bashrc" >/dev/null || die ".bashrc missing bash completion setup"
  grep -F 'starship init bash' "$LABWC_TARGET_HOME/.bashrc" >/dev/null || die ".bashrc missing starship init"
  grep -F 'compinit' "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing compinit"
  grep -F 'starship init zsh' "$LABWC_TARGET_HOME/.zshrc" >/dev/null || die ".zshrc missing starship init"
}

verify_install() {
  verify_packages
  verify_paths
  verify_services_enabled
  verify_greeter_user
  verify_ownership
  verify_labwc_config_semantics
  verify_shell_config_semantics
  log_info "verification completed"
}
