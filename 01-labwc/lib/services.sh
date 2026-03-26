#!/usr/bin/env bash

ensure_greeter_user() {
  if getent passwd greeter >/dev/null 2>&1; then
    return 0
  fi
  run_cmd useradd \
    --system \
    --home-dir /nonexistent \
    --no-create-home \
    --shell /usr/sbin/nologin \
    greeter
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
  render_template_to_file "$SCRIPT_DIR/templates/greetd-config.toml.tpl" "/etc/greetd/config.toml" 0644
  render_template_to_file "$SCRIPT_DIR/templates/labwc.desktop.tpl" "/usr/share/wayland-sessions/labwc.desktop" 0644
  render_template_to_file "$SCRIPT_DIR/templates/labwc-session.tpl" "/usr/local/bin/debian-labwc-session" 0755

  install -d -m 0755 -o greeter -g greeter /var/cache/tuigreet

  install_helper_script "$SCRIPT_DIR/bin/power-menu.sh" "/usr/local/bin/debian-labwc-power-menu"
  install_helper_script "$SCRIPT_DIR/bin/screenshot-full.sh" "/usr/local/bin/debian-labwc-screenshot-full"
  install_helper_script "$SCRIPT_DIR/bin/screenshot-region.sh" "/usr/local/bin/debian-labwc-screenshot-region"
  install_helper_script "$SCRIPT_DIR/bin/record-toggle.sh" "/usr/local/bin/debian-labwc-record-toggle"
  install_helper_script "$SCRIPT_DIR/bin/dpms.sh" "/usr/local/bin/debian-labwc-dpms"
  install_helper_script "$SCRIPT_DIR/bin/refresh-outputs.sh" "/usr/local/bin/debian-labwc-refresh-outputs"
}

enable_user_services() {
  run_cmd systemctl --global enable pipewire.service pipewire.socket
  run_cmd systemctl --global enable pipewire-pulse.service pipewire-pulse.socket
  run_cmd systemctl --global enable wireplumber.service
}

enable_system_services_only() {
  run_cmd systemctl daemon-reload
  run_cmd systemctl enable greetd.service
  run_cmd systemctl enable seatd.service
  run_cmd systemctl enable NetworkManager.service
}

enable_all_services() {
  install_root_files
  enable_system_services_only
  enable_user_services
}
