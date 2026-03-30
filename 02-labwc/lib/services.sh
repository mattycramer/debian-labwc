#!/usr/bin/env bash

if ! declare -F render_template_content >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/templates.sh"
fi

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
  local content=""
  content="$(render_template_content "$template_path")"
  run_cmd install -D -m "$mode" /dev/null "$destination"
  printf '%s' "$content" >"$destination"
  run_cmd chmod "$mode" "$destination"
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
    runuser -u "$LABWC_TARGET_USER" -- bash "$SCRIPT_DIR/libexec/ensure-gpg-key.sh"
  stage_target_user_gpg_secret_seed "$gpg_passphrase"
}

stage_target_user_gpg_secret_seed() {
  local gpg_passphrase="$1"
  local state_dir="$LABWC_TARGET_HOME/.local/state/labwc-session"
  local seed_path="$state_dir/kwallet-session-gpg-passphrase.seed"
  [[ -n "$gpg_passphrase" ]] || return 0
  run_cmd install -d -m 0700 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" "$state_dir"
  run_cmd install -D -m 0600 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" /dev/null "$seed_path"
  printf '%s' "$gpg_passphrase" >"$seed_path"
  run_cmd chown "$LABWC_TARGET_USER:$LABWC_TARGET_USER" "$seed_path"
  run_cmd chmod 0600 "$seed_path"
}

install_root_files() {
  validate_greetd_settings
  ensure_greeter_user
  ensure_greeter_runtime_dirs
  render_template_to_file "$(config_system_template_path "greetd/config.toml")" "/etc/greetd/config.toml" 0644
  render_template_to_file "$(config_system_template_path "greetd/10-vt.conf")" "/etc/systemd/system/greetd.service.d/10-vt.conf" 0644
  render_template_to_file "$(config_system_template_path "usr/share/wayland-sessions/labwc.desktop")" "/usr/share/wayland-sessions/labwc.desktop" 0644
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-session")" "/usr/local/bin/labwc-session" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-power-menu")" "/usr/local/bin/labwc-power-menu" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-screenshot-full")" "/usr/local/bin/labwc-screenshot-full" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-screenshot-region")" "/usr/local/bin/labwc-screenshot-region" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-record-toggle")" "/usr/local/bin/labwc-record-toggle" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-dpms")" "/usr/local/bin/labwc-dpms" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-refresh-outputs")" "/usr/local/bin/labwc-refresh-outputs" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-lock")" "/usr/local/bin/labwc-lock" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-launcher-menu")" "/usr/local/bin/labwc-launcher-menu" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-module-menu")" "/usr/local/bin/labwc-module-menu" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-player-status")" "/usr/local/bin/labwc-player-status" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/thunar-extract-here")" "/usr/local/bin/thunar-extract-here" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-unlock-gpg-key")" "/usr/local/bin/labwc-unlock-gpg-key" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-workspacectl")" "/usr/local/bin/labwc-workspacectl" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-workspace-activate")" "/usr/local/bin/labwc-workspace-activate" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-workspace-send")" "/usr/local/bin/labwc-workspace-send" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-workspace-state")" "/usr/local/bin/labwc-workspace-state" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-workspace-status")" "/usr/local/bin/labwc-workspace-status" 0755
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
  run_cmd systemctl enable switcheroo-control.service
  run_cmd systemctl enable udisks2.service
  run_cmd systemctl enable upower.service
  run_cmd systemctl restart polkit.service >/dev/null 2>&1 || true
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
  remove_if_present "$LABWC_TARGET_HOME/.config/Thunar"
  remove_if_present "$LABWC_TARGET_HOME/.config/kanshi"
  remove_if_present "$LABWC_TARGET_HOME/.config/wofi"
  remove_if_present "$LABWC_TARGET_HOME/.config/mako"
  remove_if_present "$LABWC_TARGET_HOME/.config/fzf"
  remove_if_present "$LABWC_TARGET_HOME/.config/swaylock"
  remove_if_present "$LABWC_TARGET_HOME/.config/foot"
  remove_if_present "$LABWC_TARGET_HOME/.config/kitty"
  remove_if_present "$LABWC_TARGET_HOME/.config/gammastep"
  remove_if_present "$LABWC_TARGET_HOME/.config/xdg-desktop-portal"
  remove_if_present "$LABWC_TARGET_HOME/.config/xfce4/helpers.rc"
  remove_if_present "$LABWC_TARGET_HOME/.config/mimeapps.list"
  remove_if_present "$LABWC_TARGET_HOME/.config/kwalletrc"
  remove_if_present "$LABWC_TARGET_HOME/.config/systemd/user/gpg-agent.service.d"
  remove_if_present "$LABWC_TARGET_HOME/.config/systemd/user/xdg-desktop-portal.service.d"
  remove_if_present "$LABWC_TARGET_HOME/.config/systemd/user/xdg-desktop-portal-wlr.service.d"
  remove_if_present "$LABWC_TARGET_HOME/.config/labwc-session"
  remove_if_present "$LABWC_TARGET_HOME/.local/bin/xdg-terminal-exec"
  remove_if_present "$LABWC_TARGET_HOME/.local/state/labwc-session"
  remove_if_present "$LABWC_TARGET_HOME/.config/starship.toml"
  remove_if_present "$LABWC_TARGET_HOME/.local/share/labwc-session"
  remove_if_present "$LABWC_TARGET_HOME/.bashrc"
  remove_if_present "$LABWC_TARGET_HOME/.profile"
  remove_if_present "$LABWC_TARGET_HOME/.zshrc"
  remove_if_present "$LABWC_TARGET_HOME/.zprofile"
  remove_if_present "$LABWC_TARGET_HOME/.nanorc"
  remove_if_present "$LABWC_TARGET_HOME/.tmux.conf"
  remove_if_present "$LABWC_TARGET_HOME/.gnupg/gpg-agent.conf"

  log_info "removing installed helper scripts and session files"
  remove_if_present "/usr/local/bin/labwc-session"
  remove_if_present "/usr/local/bin/labwc-power-menu"
  remove_if_present "/usr/local/bin/labwc-screenshot-full"
  remove_if_present "/usr/local/bin/labwc-screenshot-region"
  remove_if_present "/usr/local/bin/labwc-record-toggle"
  remove_if_present "/usr/local/bin/labwc-dpms"
  remove_if_present "/usr/local/bin/labwc-refresh-outputs"
  remove_if_present "/usr/local/bin/labwc-lock"
  remove_if_present "/usr/local/bin/labwc-launcher-menu"
  remove_if_present "/usr/local/bin/labwc-module-menu"
  remove_if_present "/usr/local/bin/labwc-player-status"
  remove_if_present "/usr/local/bin/thunar-extract-here"
  remove_if_present "/usr/local/bin/labwc-unlock-gpg-key"
  remove_if_present "/usr/local/bin/labwc-workspacectl"
  remove_if_present "/usr/local/bin/labwc-workspace-activate"
  remove_if_present "/usr/local/bin/labwc-workspace-send"
  remove_if_present "/usr/local/bin/labwc-workspace-state"
  remove_if_present "/usr/local/bin/labwc-workspace-status"
  remove_if_present "/usr/share/wayland-sessions/labwc.desktop"
  remove_if_present "/etc/greetd/config.toml"
  remove_if_present "/etc/systemd/system/greetd.service.d/10-vt.conf"
  remove_if_present "$SID_SOURCE_PATH"
  remove_if_present "$SID_PREFERENCES_PATH"
  remove_labwc_tweaks_install
  remove_keepsecret_install
  rmdir --ignore-fail-on-non-empty "/etc/systemd/system/greetd.service.d" >/dev/null 2>&1 || true

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
