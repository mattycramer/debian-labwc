#!/usr/bin/env bash

readonly POLKIT_TMPFILES_PATH="/etc/tmpfiles.d/debian-labwc-polkit.conf"
readonly UDISKS2_DROPIN_DIR="/etc/systemd/system/udisks2.service.d"
readonly UDISKS2_DROPIN_PATH="${UDISKS2_DROPIN_DIR}/10-polkit.conf"

ensure_greeter_user() {
  if getent passwd greeter >/dev/null 2>&1; then
    return 0
  fi
  run_cmd useradd \
    --system \
    --home-dir /var/lib/greetd/greeter \
    --no-create-home \
    --shell /usr/sbin/nologin \
    greeter
}

ensure_polkitd_service_account() {
  if ! getent group polkitd >/dev/null 2>&1; then
    run_cmd groupadd --system polkitd
  fi
  if getent passwd polkitd >/dev/null 2>&1; then
    return 0
  fi
  run_cmd useradd \
    --system \
    --gid polkitd \
    --home-dir / \
    --no-create-home \
    --shell /usr/sbin/nologin \
    --comment "User for polkitd" \
    polkitd
}

install_polkit_runtime_layout() {
  run_cmd install -d -m 0755 /usr/local/share/polkit-1/rules.d
  cat >"$POLKIT_TMPFILES_PATH" <<'EOF'
d /run/polkit-1 0755 root root -
d /run/polkit-1/rules.d 0755 root root -
EOF
  run_cmd chmod 0644 "$POLKIT_TMPFILES_PATH"
  run_cmd systemd-tmpfiles --create "$POLKIT_TMPFILES_PATH"
}

install_udisks2_polkit_dropin() {
  local content
  content="$(cat <<'EOF'
[Unit]
Wants=polkit.service
After=polkit.service dbus.service
EOF
)"
  run_cmd install -d -m 0755 "$UDISKS2_DROPIN_DIR"
  printf '%s' "$content" >"$UDISKS2_DROPIN_PATH"
  run_cmd chmod 0644 "$UDISKS2_DROPIN_PATH"
}

ensure_greeter_runtime_dirs() {
  run_cmd install -d -m 0755 -o greeter -g greeter /var/lib/greetd/greeter
  run_cmd install -d -m 0755 -o greeter -g greeter /var/lib/greetd/greeter/.cache
  run_cmd install -d -m 0755 -o greeter -g greeter /var/lib/greetd/greeter/.config
  run_cmd install -d -m 0755 -o greeter -g greeter /var/lib/greetd/greeter/.config/autostart
  run_cmd install -d -m 0755 -o greeter -g greeter /var/lib/greetd/greeter/.local
  run_cmd install -d -m 0755 -o greeter -g greeter /var/lib/greetd/greeter/.local/state
  run_cmd install -d -m 0755 -o greeter -g greeter /var/lib/greetd/greeter/.local/share
  run_cmd install -d -m 0755 -o greeter -g greeter /var/lib/greetd/greeter/.local/share/flatpak/db
}

validate_greetd_settings() {
  [[ "${LABWC_GREETD_VT:-}" =~ ^[1-9][0-9]*$ ]] || die "LABWC_GREETD_VT must be a positive integer, found '${LABWC_GREETD_VT:-}'"
}

render_template_to_file() {
  local template_path="$1"
  local destination="$2"
  local mode="$3"
  run_cmd install -D -m "$mode" /dev/null "$destination"
  sed \
    -e "s|@GREETD_VT@|$LABWC_GREETD_VT|g" \
    -e "s|@TARGET_USER@|$LABWC_TARGET_USER|g" \
    -e "s|@TARGET_HOME@|$LABWC_TARGET_HOME|g" \
    -e "s|@XCURSOR_THEME@|$LABWC_XCURSOR_THEME|g" \
    -e "s|@XCURSOR_SIZE@|$LABWC_XCURSOR_SIZE|g" \
    -e "s|@SESSION_WRAPPER@|/usr/local/bin/debian-labwc-session|g" \
    "$template_path" >"$destination"
  run_cmd chmod "$mode" "$destination"
}

install_helper_script() {
  local source_path="$1"
  local destination="$2"
  run_cmd install -D -m 0755 /dev/null "$destination"
  sed \
    -e "s|@TARGET_HOME@|$LABWC_TARGET_HOME|g" \
    -e "s|@INTERNAL_OUTPUT@|${LABWC_INTERNAL_OUTPUT}|g" \
    -e "s|@EXTERNAL_OUTPUT@|${LABWC_EXTERNAL_OUTPUT}|g" \
    -e "s|@INTERNAL_MODE@|${LABWC_INTERNAL_MODE}|g" \
    -e "s|@EXTERNAL_MODE@|${LABWC_EXTERNAL_MODE}|g" \
    -e "s|@INTERNAL_HZ@|${LABWC_INTERNAL_HZ}|g" \
    -e "s|@EXTERNAL_HZ@|${LABWC_EXTERNAL_HZ}|g" \
    "$source_path" >"$destination"
  run_cmd chmod 0755 "$destination"
}

bootstrap_target_user_gpg_key() {
  local gpg_passphrase="${KWALLET_SESSION_GPG_PASSWD:-}"
  if [[ -z "$gpg_passphrase" ]]; then
    [[ -t 0 ]] || die "KWALLET_SESSION_GPG_PASSWD is empty and no interactive terminal is available for prompting"
    IFS= read -r -s -p "No GPG Encryption Password Set. Enter New Password: " gpg_passphrase
    printf '\n'
  fi
  [[ -n "$gpg_passphrase" ]] || die "no GPG encryption password was provided"
  run_cmd env \
    HOME="$LABWC_TARGET_HOME" \
    USER="$LABWC_TARGET_USER" \
    LOGNAME="$LABWC_TARGET_USER" \
    GNUPGHOME="$LABWC_TARGET_HOME/.gnupg" \
    KWALLET_SESSION_GPG_PASSWD="$gpg_passphrase" \
    LABWC_TARGET_USER="$LABWC_TARGET_USER" \
    LABWC_GPG_KEY_REALNAME="${LABWC_GPG_KEY_REALNAME:-}" \
    LABWC_GPG_KEY_EMAIL="${LABWC_GPG_KEY_EMAIL:-}" \
    LABWC_GPG_KEY_EXPIRE="${LABWC_GPG_KEY_EXPIRE:-2y}" \
    runuser -u "$LABWC_TARGET_USER" -- bash "$SCRIPT_DIR/bin/ensure-gpg-key.sh"
}

install_root_files() {
  validate_greetd_settings
  ensure_greeter_user
  ensure_greeter_runtime_dirs
  install_polkit_runtime_layout
  install_udisks2_polkit_dropin
  render_template_to_file "$SCRIPT_DIR/templates/greetd-config.toml.tpl" "/etc/greetd/config.toml" 0644
  render_template_to_file "$SCRIPT_DIR/templates/greetd-vt.conf.tpl" "/etc/systemd/system/greetd.service.d/10-vt.conf" 0644
  render_template_to_file "$SCRIPT_DIR/templates/labwc.desktop.tpl" "/usr/share/wayland-sessions/labwc.desktop" 0644
  render_template_to_file "$SCRIPT_DIR/templates/labwc-session.tpl" "/usr/local/bin/debian-labwc-session" 0755

  install_helper_script "$SCRIPT_DIR/bin/power-menu.sh" "/usr/local/bin/debian-labwc-power-menu"
  install_helper_script "$SCRIPT_DIR/bin/screenshot-full.sh" "/usr/local/bin/debian-labwc-screenshot-full"
  install_helper_script "$SCRIPT_DIR/bin/screenshot-region.sh" "/usr/local/bin/debian-labwc-screenshot-region"
  install_helper_script "$SCRIPT_DIR/bin/record-toggle.sh" "/usr/local/bin/debian-labwc-record-toggle"
  install_helper_script "$SCRIPT_DIR/bin/dpms.sh" "/usr/local/bin/debian-labwc-dpms"
  install_helper_script "$SCRIPT_DIR/bin/refresh-outputs.sh" "/usr/local/bin/debian-labwc-refresh-outputs"
  install_helper_script "$SCRIPT_DIR/bin/launcher-menu.sh" "/usr/local/bin/debian-labwc-launcher-menu"
  install_helper_script "$SCRIPT_DIR/bin/module-menu.sh" "/usr/local/bin/debian-labwc-module-menu"
  install_helper_script "$SCRIPT_DIR/bin/player-status.sh" "/usr/local/bin/debian-labwc-player-status"
  install_helper_script "$SCRIPT_DIR/bin/unlock-gpg-key.sh" "/usr/local/bin/debian-labwc-unlock-gpg-key"
  install_helper_script "$SCRIPT_DIR/bin/workspace-activate.sh" "/usr/local/bin/debian-labwc-workspace-activate"
  install_helper_script "$SCRIPT_DIR/bin/workspace-send.sh" "/usr/local/bin/debian-labwc-workspace-send"
  install_helper_script "$SCRIPT_DIR/bin/workspace-state.sh" "/usr/local/bin/debian-labwc-workspace-state"
  install_helper_script "$SCRIPT_DIR/bin/workspace-status.sh" "/usr/local/bin/debian-labwc-workspace-status"
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

unit_install_values() {
  local unit_path="$1"
  local field_name="$2"
  awk -F= -v field_name="$field_name" '
    /^\[Install\]/ {in_install=1; next}
    /^\[/ && $0 != "[Install]" {in_install=0}
    in_install && $1 == field_name {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
      count = split($2, values, /[[:space:]]+/)
      for (i = 1; i <= count; i++) {
        if (values[i] != "") {
          print values[i]
        }
      }
    }
  ' "$unit_path"
}

create_target_user_unit_link() {
  local unit_name="$1"
  local unit_path="$2"
  local target_name="$3"
  local wants_dir="$LABWC_TARGET_HOME/.config/systemd/user/${target_name}.wants"
  run_cmd install -d -m 0755 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" "$wants_dir"
  run_cmd ln -sfn "$unit_path" "$wants_dir/$unit_name"
  run_cmd chown -h "$LABWC_TARGET_USER:$LABWC_TARGET_USER" "$wants_dir/$unit_name"
}

enable_target_user_unit() {
  local unit_name="$1"
  local unit_path
  local install_target
  local also_unit
  unit_path="$(resolve_user_unit_path "$unit_name")"
  while IFS= read -r install_target; do
    [[ -n "$install_target" ]] || continue
    create_target_user_unit_link "$unit_name" "$unit_path" "$install_target"
  done < <(unit_install_values "$unit_path" "WantedBy")
  while IFS= read -r also_unit; do
    [[ -n "$also_unit" ]] || continue
    enable_target_user_unit "$also_unit"
  done < <(unit_install_values "$unit_path" "Also")
}

enable_user_services() {
  enable_target_user_unit pipewire.socket
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
  run_cmd systemctl enable udisks2.service
  run_cmd systemctl enable upower.service
  run_cmd systemctl start polkit.service
}

enable_all_services() {
  install_root_files
  enable_system_services_only
  enable_user_services
}

remove_if_present() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    run_cmd rm -rf -- "$path"
  fi
}

disable_target_user_unit() {
  local unit_name="$1"
  local systemd_user_dir="$LABWC_TARGET_HOME/.config/systemd/user"
  local wants_path
  while IFS= read -r wants_path; do
    remove_if_present "$wants_path"
  done < <(find "$systemd_user_dir" -maxdepth 2 \( -type l -o -type f \) -name "$unit_name" 2>/dev/null | sort)
}

nuke_all_state() {
  log_info "removing generated user config"
  remove_if_present "$LABWC_TARGET_HOME/.config/labwc"
  remove_if_present "$LABWC_TARGET_HOME/.config/waybar"
  remove_if_present "$LABWC_TARGET_HOME/.config/kanshi"
  remove_if_present "$LABWC_TARGET_HOME/.config/wofi"
  remove_if_present "$LABWC_TARGET_HOME/.config/mako"
  remove_if_present "$LABWC_TARGET_HOME/.config/fzf"
  remove_if_present "$LABWC_TARGET_HOME/.config/swaylock"
  remove_if_present "$LABWC_TARGET_HOME/.config/foot"
  remove_if_present "$LABWC_TARGET_HOME/.config/gammastep"
  remove_if_present "$LABWC_TARGET_HOME/.config/xdg-desktop-portal"
  remove_if_present "$LABWC_TARGET_HOME/.config/systemd/user/xdg-desktop-portal.service.d"
  remove_if_present "$LABWC_TARGET_HOME/.config/systemd/user/xdg-desktop-portal-wlr.service.d"
  remove_if_present "$LABWC_TARGET_HOME/.config/debian-labwc"
  remove_if_present "$LABWC_TARGET_HOME/.local/state/debian-labwc"
  remove_if_present "$LABWC_TARGET_HOME/.config/starship.toml"
  remove_if_present "$LABWC_TARGET_HOME/.local/share/debian-labwc"
  remove_if_present "$LABWC_TARGET_HOME/.bashrc"
  remove_if_present "$LABWC_TARGET_HOME/.profile"
  remove_if_present "$LABWC_TARGET_HOME/.zshrc"
  remove_if_present "$LABWC_TARGET_HOME/.zprofile"
  remove_if_present "$LABWC_TARGET_HOME/.nanorc"
  remove_if_present "$LABWC_TARGET_HOME/.tmux.conf"

  log_info "removing installed helper scripts and session files"
  remove_if_present "/usr/local/bin/debian-labwc-session"
  remove_if_present "/usr/local/bin/debian-labwc-power-menu"
  remove_if_present "/usr/local/bin/debian-labwc-screenshot-full"
  remove_if_present "/usr/local/bin/debian-labwc-screenshot-region"
  remove_if_present "/usr/local/bin/debian-labwc-record-toggle"
  remove_if_present "/usr/local/bin/debian-labwc-dpms"
  remove_if_present "/usr/local/bin/debian-labwc-refresh-outputs"
  remove_if_present "/usr/local/bin/debian-labwc-launcher-menu"
  remove_if_present "/usr/local/bin/debian-labwc-module-menu"
  remove_if_present "/usr/local/bin/debian-labwc-player-status"
  remove_if_present "/usr/local/bin/debian-labwc-unlock-gpg-key"
  remove_if_present "/usr/local/bin/debian-labwc-workspace-activate"
  remove_if_present "/usr/local/bin/debian-labwc-workspace-send"
  remove_if_present "/usr/local/bin/debian-labwc-workspace-state"
  remove_if_present "/usr/local/bin/debian-labwc-workspace-status"
  remove_if_present "/usr/share/wayland-sessions/labwc.desktop"
  remove_if_present "/usr/local/share/polkit-1/rules.d"
  remove_if_present "$POLKIT_TMPFILES_PATH"
  remove_if_present "$UDISKS2_DROPIN_PATH"
  remove_if_present "/etc/greetd/config.toml"
  remove_if_present "/etc/systemd/system/greetd.service.d/10-vt.conf"
  rmdir --ignore-fail-on-non-empty "/etc/systemd/system/greetd.service.d" >/dev/null 2>&1 || true
  rmdir --ignore-fail-on-non-empty "$UDISKS2_DROPIN_DIR" >/dev/null 2>&1 || true
  rmdir --ignore-fail-on-non-empty "/usr/local/share/polkit-1" >/dev/null 2>&1 || true
  remove_if_present "/run/polkit-1/rules.d"
  rmdir --ignore-fail-on-non-empty "/run/polkit-1" >/dev/null 2>&1 || true

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
  remove_if_present "/var/lib/greetd/greeter"
  if getent passwd greeter >/dev/null 2>&1; then
    userdel greeter >/dev/null 2>&1 || true
  fi
}
