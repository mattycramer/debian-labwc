#!/usr/bin/env bash

if ! declare -F render_template_content >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/templates.sh"
fi

render_user_file() {
  local destination="$1"
  local content="$2"
  run_cmd install -D -m 0644 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" /dev/null "$destination"
  printf '%s' "$content" >"$destination"
  run_cmd chown "$LABWC_TARGET_USER:$LABWC_TARGET_USER" "$destination"
}

render_user_private_file() {
  local destination="$1"
  local content="$2"
  run_cmd install -D -m 0600 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" /dev/null "$destination"
  printf '%s' "$content" >"$destination"
  run_cmd chown "$LABWC_TARGET_USER:$LABWC_TARGET_USER" "$destination"
  run_cmd chmod 0600 "$destination"
}

render_user_script() {
  local destination="$1"
  local content="$2"
  run_cmd install -D -m 0755 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" /dev/null "$destination"
  printf '%s' "$content" >"$destination"
  run_cmd chown "$LABWC_TARGET_USER:$LABWC_TARGET_USER" "$destination"
  run_cmd chmod 0755 "$destination"
}

render_home_template_file() {
  local relative_path="$1"
  local content
  content="$(render_template_content "$(config_home_template_path "$relative_path")")"
  render_user_file "$LABWC_TARGET_HOME/$relative_path" "$content"
}

render_home_template_private_file() {
  local relative_path="$1"
  local content
  content="$(render_template_content "$(config_home_template_path "$relative_path")")"
  render_user_private_file "$LABWC_TARGET_HOME/$relative_path" "$content"
}

render_home_template_script() {
  local relative_path="$1"
  local content
  content="$(render_template_content "$(config_home_template_path "$relative_path")")"
  render_user_script "$LABWC_TARGET_HOME/$relative_path" "$content"
}

render_labwc_environment() {
  render_home_template_file ".config/labwc/environment"
}

wallpaper_source_path_for_prefix() {
  local prefix="$1"
  local wallpaper_path=""
  wallpaper_path="$(
    find "$SCRIPT_DIR/wallpaper" -maxdepth 1 -type f -name "${prefix}-*" | LC_ALL=C sort | head -n 1
  )"
  if [[ -z "$wallpaper_path" ]]; then
    wallpaper_path="$(
      find "$SCRIPT_DIR/wallpaper" -maxdepth 1 -type f | LC_ALL=C sort | head -n 1
    )"
  fi
  [[ -n "$wallpaper_path" ]] || die "missing wallpaper asset under '$SCRIPT_DIR/wallpaper'"
  printf '%s\n' "$wallpaper_path"
}

background_wallpaper_source_path() {
  wallpaper_source_path_for_prefix "wall"
}

lock_wallpaper_source_path() {
  wallpaper_source_path_for_prefix "lock"
}

wallpaper_target_path() {
  local wallpaper_source_path="$1"
  printf '%s/.local/share/labwc-session/%s\n' "$LABWC_TARGET_HOME" "$(basename "$wallpaper_source_path")"
}

background_wallpaper_target_path() {
  local wallpaper_source_path
  wallpaper_source_path="$(background_wallpaper_source_path)"
  wallpaper_target_path "$wallpaper_source_path"
}

lock_wallpaper_target_path() {
  local wallpaper_source_path
  wallpaper_source_path="$(lock_wallpaper_source_path)"
  wallpaper_target_path "$wallpaper_source_path"
}

ensure_user_base_dirs() {
  run_cmd install -d -m 0755 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" \
    "$LABWC_TARGET_HOME/.config" \
    "$LABWC_TARGET_HOME/.local" \
    "$LABWC_TARGET_HOME/.local/bin" \
    "$LABWC_TARGET_HOME/.local/share" \
    "$LABWC_TARGET_HOME/.local/state"
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
  render_home_template_file ".config/user-dirs.dirs"
  render_home_template_file ".config/user-dirs.locale"
}

render_shell_startup_files() {
  render_home_template_file ".bashrc"
  render_home_template_file ".profile"
  render_home_template_file ".zshrc"
  render_home_template_file ".zprofile"
  render_home_template_file ".config/starship.toml"
  render_home_template_file ".nanorc"
}

render_xfce_helpers() {
  render_home_template_file ".config/xfce4/helpers.rc"
}

render_mimeapps() {
  render_home_template_file ".config/mimeapps.list"
}

render_thunar_config() {
  render_home_template_file ".config/Thunar/uca.xml"
}

render_xdg_terminal_exec() {
  render_home_template_script ".local/bin/xdg-terminal-exec"
}

render_tmux_config() {
  render_home_template_file ".tmux.conf"
}

render_fzf_config() {
  render_home_template_file ".config/fzf/default-opts"
  render_home_template_script ".config/fzf/preview.sh"
}

render_labwc_rc_xml() {
  case "${LABWC_NATURAL_SCROLL:-}" in
    yes|no) ;;
    *) die "LABWC_NATURAL_SCROLL must be 'yes' or 'no', found '${LABWC_NATURAL_SCROLL:-}'" ;;
  esac
  render_home_template_file ".config/labwc/rc.xml"
}

render_labwc_menu_xml() {
  render_home_template_file ".config/labwc/menu.xml"
}

render_labwc_autostart() {
  render_home_template_script ".config/labwc/autostart"
}

render_labwc_shutdown() {
  render_home_template_script ".config/labwc/shutdown"
}

render_gpg_agent_override() {
  render_home_template_file ".config/systemd/user/gpg-agent.service.d/override.conf"
}

render_portal_unit_overrides() {
  render_home_template_file ".config/systemd/user/xdg-desktop-portal.service.d/override.conf"
  render_home_template_file ".config/systemd/user/xdg-desktop-portal-wlr.service.d/override.conf"
}

render_gpg_agent_config() {
  [[ "${KWALLET_SESSION_GPG_CACHE_TTL_SEC:-}" =~ ^[1-9][0-9]*$ ]] || die "KWALLET_SESSION_GPG_CACHE_TTL_SEC must be a positive integer, found '${KWALLET_SESSION_GPG_CACHE_TTL_SEC:-}'"
  render_home_template_private_file ".gnupg/gpg-agent.conf"
}

render_kwallet_config() {
  render_home_template_file ".config/kwalletrc"
}

render_waybar_scripts() {
  render_home_template_script ".config/waybar/scripts/pending-updates.sh"
  render_home_template_script ".config/waybar/scripts/run-upgrades.sh"
  render_home_template_script ".config/waybar/scripts/gpu-launch.sh"
}

render_waybar_config() {
  render_home_template_file ".config/waybar/config.jsonc"
}

render_waybar_style() {
  render_home_template_file ".config/waybar/style.css"
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

mode_width() {
  local mode_name="$1"
  if [[ "$mode_name" =~ ^([0-9]+)x[0-9]+$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  printf '%s\n' "1920"
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
      local external_line dual_external_line dual_internal_line external_width
      external_width="$(mode_width "${LABWC_EXTERNAL_MODE}")"
      external_line="$(kanshi_output_line "$external_output" "${LABWC_EXTERNAL_MODE}" "${LABWC_EXTERNAL_HZ}" "0,0" "enable")"
      dual_external_line="$(kanshi_output_line "$external_output" "${LABWC_EXTERNAL_MODE}" "${LABWC_EXTERNAL_HZ}" "0,0" "enable")"
      dual_internal_line="$(kanshi_output_line "$internal_output" "${LABWC_INTERNAL_MODE}" "${LABWC_INTERNAL_HZ}" "${external_width},0" "enable")"
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
  KANSHI_INTERNAL_PROFILE="$internal_profile" \
  KANSHI_EXTERNAL_CLAUSE="$external_clause" \
    render_home_template_file ".config/kanshi/config"
}

render_wofi() {
  render_home_template_file ".config/wofi/config"
  render_home_template_file ".config/wofi/style.css"
}

render_mako() {
  render_home_template_file ".config/mako/config"
}

render_swaylock() {
  render_home_template_file ".config/swaylock/config"
}

render_foot() {
  render_home_template_file ".config/foot/foot.ini"
}

render_kitty() {
  render_home_template_file ".config/kitty/kitty.conf"
}

render_gammastep() {
  render_home_template_file ".config/gammastep/config"
}

render_portals() {
  render_home_template_file ".config/xdg-desktop-portal/portals.conf"
}

install_wallpaper() {
  local wallpaper_source_path wallpaper_name
  run_cmd install -d -m 0755 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" "$LABWC_TARGET_HOME/.local/share/labwc-session"
  while IFS= read -r wallpaper_source_path; do
    [[ -n "$wallpaper_source_path" ]] || continue
    wallpaper_name="$(basename "$wallpaper_source_path")"
    run_cmd install -m 0644 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" "$wallpaper_source_path" "$LABWC_TARGET_HOME/.local/share/labwc-session/$wallpaper_name"
  done < <(find "$SCRIPT_DIR/wallpaper" -maxdepth 1 -type f | LC_ALL=C sort)
  require_file "$(background_wallpaper_target_path)"
  require_file "$(lock_wallpaper_target_path)"
}

render_all_configs() {
  local config_root="$LABWC_TARGET_HOME/.config"
  ensure_user_base_dirs
  run_cmd install -d -m 0755 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" \
    "$config_root/labwc" \
    "$config_root/waybar" \
    "$config_root/waybar/scripts" \
    "$config_root/kanshi" \
    "$config_root/kitty" \
    "$config_root/Thunar" \
    "$config_root/xfce4" \
    "$config_root/wofi" \
    "$config_root/mako" \
    "$config_root/fzf" \
    "$config_root/swaylock" \
    "$config_root/foot" \
    "$config_root/gammastep" \
    "$config_root/xdg-desktop-portal" \
    "$config_root/labwc-session" \
    "$config_root/systemd/user/gpg-agent.service.d" \
    "$config_root/systemd/user/xdg-desktop-portal.service.d" \
    "$config_root/systemd/user/xdg-desktop-portal-wlr.service.d" \
    "$config_root/systemd/user" \
    "$config_root"
  run_cmd install -d -m 0700 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" "$LABWC_TARGET_HOME/.gnupg"

  render_home_dirs
  render_shell_startup_files
  render_thunar_config
  render_xfce_helpers
  render_mimeapps
  render_xdg_terminal_exec
  render_tmux_config
  render_fzf_config
  install_wallpaper
  render_labwc_environment
  render_labwc_rc_xml
  render_labwc_menu_xml
  render_labwc_autostart
  render_labwc_shutdown
  render_gpg_agent_override
  render_gpg_agent_config
  render_kwallet_config
  render_portal_unit_overrides
  render_waybar_scripts
  render_waybar_config
  render_waybar_style
  render_kanshi_config
  render_wofi
  render_mako
  render_swaylock
  render_foot
  render_kitty
  render_gammastep
  render_portals
  run_cmd chown -R "$LABWC_TARGET_USER:$LABWC_TARGET_USER" "$LABWC_TARGET_HOME/.config" "$LABWC_TARGET_HOME/.local"
}
