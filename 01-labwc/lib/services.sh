#!/usr/bin/env bash

ensure_greeter_user() {
  if getent passwd greeter >/dev/null 2>&1; then
    return 0
  fi
  run_cmd useradd \
    --system \
    --home-dir /var/cache/tuigreet \
    --no-create-home \
    --shell /usr/sbin/nologin \
    greeter
}

ensure_greeter_runtime_dirs() {
  install -d -m 0755 -o greeter -g greeter /var/cache/tuigreet
  install -d -m 0755 -o greeter -g greeter /var/cache/tuigreet/.cache
  install -d -m 0755 -o greeter -g greeter /var/cache/tuigreet/.local
  install -d -m 0755 -o greeter -g greeter /var/cache/tuigreet/.local/state
}

render_template_to_file() {
  local template_path="$1"
  local destination="$2"
  local mode="$3"
  local temp_file
  temp_file="$(mktemp)"
  sed \
    -e "s|@TARGET_USER@|$LABWC_TARGET_USER|g" \
    -e "s|@TARGET_HOME@|$LABWC_TARGET_HOME|g" \
    -e "s|@RUNTIME_ENV_PATH@|$LABWC_TARGET_HOME/.config/debian-labwc/runtime.env|g" \
    -e "s|@SESSION_WRAPPER@|/usr/local/bin/debian-labwc-session|g" \
    "$template_path" >"$temp_file"
  install -D -m "$mode" "$temp_file" "$destination"
  rm -f -- "$temp_file"
}

install_helper_script() {
  local source_path="$1"
  local destination="$2"
  local temp_file
  temp_file="$(mktemp)"
  sed \
    -e "s|@TARGET_HOME@|$LABWC_TARGET_HOME|g" \
    -e "s|@RUNTIME_ENV_PATH@|$LABWC_TARGET_HOME/.config/debian-labwc/runtime.env|g" \
    -e "s|@REPO_ENV_PATH@|$SCRIPT_DIR/.env|g" \
    "$source_path" >"$temp_file"
  install -D -m 0755 "$temp_file" "$destination"
  rm -f -- "$temp_file"
}

install_root_files() {
  ensure_greeter_user
  ensure_greeter_runtime_dirs
  render_template_to_file "$SCRIPT_DIR/templates/greetd-config.toml.tpl" "/etc/greetd/config.toml" 0644
  render_template_to_file "$SCRIPT_DIR/templates/labwc.desktop.tpl" "/usr/share/wayland-sessions/labwc.desktop" 0644
  render_template_to_file "$SCRIPT_DIR/templates/labwc-session.tpl" "/usr/local/bin/debian-labwc-session" 0755

  install_helper_script "$SCRIPT_DIR/bin/power-menu.sh" "/usr/local/bin/debian-labwc-power-menu"
  install_helper_script "$SCRIPT_DIR/bin/screenshot-full.sh" "/usr/local/bin/debian-labwc-screenshot-full"
  install_helper_script "$SCRIPT_DIR/bin/screenshot-region.sh" "/usr/local/bin/debian-labwc-screenshot-region"
  install_helper_script "$SCRIPT_DIR/bin/record-toggle.sh" "/usr/local/bin/debian-labwc-record-toggle"
  install_helper_script "$SCRIPT_DIR/bin/dpms.sh" "/usr/local/bin/debian-labwc-dpms"
  install_helper_script "$SCRIPT_DIR/bin/refresh-outputs.sh" "/usr/local/bin/debian-labwc-refresh-outputs"
}

resolve_user_unit_path() {
  local unit_name="$1"
  local candidate
  for candidate in "/usr/lib/systemd/user/$unit_name" "/lib/systemd/user/$unit_name"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  die "missing systemd user unit: $unit_name"
}

enable_target_user_unit() {
  local unit_name="$1"
  local unit_path
  local wants_dir="$LABWC_TARGET_HOME/.config/systemd/user/default.target.wants"
  unit_path="$(resolve_user_unit_path "$unit_name")"
  install -d -m 0755 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" "$wants_dir"
  ln -sfn "$unit_path" "$wants_dir/$unit_name"
  chown -h "$LABWC_TARGET_USER:$LABWC_TARGET_USER" "$wants_dir/$unit_name"
}

enable_user_services() {
  enable_target_user_unit pipewire.service
  enable_target_user_unit pipewire.socket
  enable_target_user_unit pipewire-pulse.service
  enable_target_user_unit pipewire-pulse.socket
  enable_target_user_unit wireplumber.service
  if command -v chsh >/dev/null 2>&1; then
    local current_shell
    current_shell="$(getent passwd "$LABWC_TARGET_USER" | awk -F: '{print $7}')"
    if [[ "$current_shell" != "/usr/bin/zsh" && "$current_shell" != "/bin/zsh" ]]; then
      chsh -s "$(command -v zsh)" "$LABWC_TARGET_USER" >/dev/null 2>&1 || true
    fi
  fi
}

enable_system_services_only() {
  run_cmd systemctl daemon-reload
  run_cmd systemctl set-default graphical.target
  run_cmd systemctl enable greetd.service
  run_cmd systemctl enable seatd.service
  run_cmd systemctl enable NetworkManager.service
}

enable_all_services() {
  install_root_files
  enable_system_services_only
  enable_user_services
}

remove_if_present() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    rm -rf -- "$path"
  fi
}

disable_target_user_unit() {
  local unit_name="$1"
  local wants_path="$LABWC_TARGET_HOME/.config/systemd/user/default.target.wants/$unit_name"
  remove_if_present "$wants_path"
}

nuke_all_state() {
  log_info "removing generated user config"
  remove_if_present "$LABWC_TARGET_HOME/.config/labwc"
  remove_if_present "$LABWC_TARGET_HOME/.config/waybar"
  remove_if_present "$LABWC_TARGET_HOME/.config/kanshi"
  remove_if_present "$LABWC_TARGET_HOME/.config/wofi"
  remove_if_present "$LABWC_TARGET_HOME/.config/mako"
  remove_if_present "$LABWC_TARGET_HOME/.config/swaylock"
  remove_if_present "$LABWC_TARGET_HOME/.config/foot"
  remove_if_present "$LABWC_TARGET_HOME/.config/gammastep"
  remove_if_present "$LABWC_TARGET_HOME/.config/xdg-desktop-portal"
  remove_if_present "$LABWC_TARGET_HOME/.config/debian-labwc"
  remove_if_present "$LABWC_TARGET_HOME/.config/starship.toml"
  remove_if_present "$LABWC_TARGET_HOME/.local/share/debian-labwc"
  remove_if_present "$LABWC_TARGET_HOME/.bashrc"
  remove_if_present "$LABWC_TARGET_HOME/.profile"
  remove_if_present "$LABWC_TARGET_HOME/.zshrc"
  remove_if_present "$LABWC_TARGET_HOME/.zprofile"

  log_info "removing installed helper scripts and session files"
  remove_if_present "/usr/local/bin/debian-labwc-session"
  remove_if_present "/usr/local/bin/debian-labwc-power-menu"
  remove_if_present "/usr/local/bin/debian-labwc-screenshot-full"
  remove_if_present "/usr/local/bin/debian-labwc-screenshot-region"
  remove_if_present "/usr/local/bin/debian-labwc-record-toggle"
  remove_if_present "/usr/local/bin/debian-labwc-dpms"
  remove_if_present "/usr/local/bin/debian-labwc-refresh-outputs"
  remove_if_present "/usr/share/wayland-sessions/labwc.desktop"
  remove_if_present "/etc/greetd/config.toml"

  log_info "removing target user systemd user unit links"
  disable_target_user_unit pipewire.service
  disable_target_user_unit pipewire.socket
  disable_target_user_unit pipewire-pulse.service
  disable_target_user_unit pipewire-pulse.socket
  disable_target_user_unit wireplumber.service

  log_info "disabling greetd and restoring multi-user target"
  systemctl disable greetd.service >/dev/null 2>&1 || true
  systemctl set-default multi-user.target >/dev/null 2>&1 || true

  log_info "removing tuigreet cache and greeter user"
  remove_if_present "/var/cache/tuigreet"
  if getent passwd greeter >/dev/null 2>&1; then
    userdel greeter >/dev/null 2>&1 || true
  fi
}
