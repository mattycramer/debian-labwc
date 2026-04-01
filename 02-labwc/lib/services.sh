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
  run_cmd install -d -m 0700 -o greeter -g greeter /var/lib/greetd/greeter
  run_cmd install -d -m 0700 -o greeter -g greeter /var/lib/greetd/greeter/.cache
  run_cmd install -d -m 0700 -o greeter -g greeter /var/lib/greetd/greeter/.config
  run_cmd install -d -m 0700 -o greeter -g greeter /var/lib/greetd/greeter/.local
  run_cmd install -d -m 0700 -o greeter -g greeter /var/lib/greetd/greeter/.local/state
  run_cmd install -d -m 0700 -o greeter -g greeter /var/lib/greetd/greeter/.local/share
}

validate_greetd_vt() {
  [[ "${LABWC_GREETD_VT:-}" =~ ^[1-9][0-9]*$ ]] || die "LABWC_GREETD_VT must be a positive integer, found '${LABWC_GREETD_VT:-}'"
}

validate_regreet_settings() {
  [[ "${GITHUB_REGREET_TAG:-}" =~ ^[A-Za-z0-9._-]+$ ]] || {
    die "GITHUB_REGREET_TAG must contain only alnum, dot, underscore, or dash, found '${GITHUB_REGREET_TAG:-}'"
  }
  [[ "${GITHUB_REGREET_TARBALL:-}" =~ ^https://github\.com/[^/]+/[^/]+/releases/download/${GITHUB_REGREET_TAG}/[^/?#]+\.tar\.gz$ ]] || {
    die "GITHUB_REGREET_TARBALL must be a GitHub release tarball for tag '${GITHUB_REGREET_TAG}', found '${GITHUB_REGREET_TARBALL:-}'"
  }
  [[ "${GITHUB_REGREET_TARBALL_SHA:-}" =~ ^[0-9a-f]{64}$ ]] || {
    die "GITHUB_REGREET_TARBALL_SHA must be a 64 character lowercase hex sha256, found '${GITHUB_REGREET_TARBALL_SHA:-}'"
  }
  [[ "${GITHUB_REGREET_COMMIT_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || {
    die "GITHUB_REGREET_COMMIT_SHA must be a 40 character lowercase hex commit sha, found '${GITHUB_REGREET_COMMIT_SHA:-}'"
  }
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

wireguard_profile_specs() {
  cat <<'EOF'
sego005-semm001|Sweden|🇸🇪
dkcp401-dkcp102|Denmark|🇩🇰
noos102-noos003|Norway|🇳🇴
fihe101-fihe003|Finland|🇫🇮
defr003-defr002|Germany|🇩🇪
gbgl001-gbgl002|UK|🇬🇧
uswa001-uswa002|USA|🇺🇸
EOF
}

wireguard_import_dir() {
  printf '%s\n' "/var/lib/labwc-session/wireguard"
}

wireguard_import_service_name() {
  printf '%s\n' "labwc-wireguard-import.service"
}

render_wireguard_profile_file() {
  local profile_name="$1"
  local destination="$2"
  local source_path="$SCRIPT_DIR/config/wireguard/${profile_name}.conf"
  local content=""

  [[ -f "$source_path" ]] || die "missing WireGuard profile template: $source_path"
  content="$(render_template_content "$source_path")"
  run_cmd install -D -m 0600 /dev/null "$destination"
  printf '%s' "$content" >"$destination"
  run_cmd chmod 0600 "$destination"
}

stage_wireguard_profiles() {
  local import_dir profile_name profile_label profile_flag rendered_path
  import_dir="$(wireguard_import_dir)"

  run_cmd install -d -m 0700 "$import_dir"
  run_cmd find "$import_dir" -maxdepth 1 -type f -name '*.conf' -delete

  while IFS='|' read -r profile_name profile_label profile_flag; do
    [[ -n "$profile_name" ]] || continue
    rendered_path="${import_dir}/${profile_name}.conf"
    render_wireguard_profile_file "$profile_name" "$rendered_path"
  done < <(wireguard_profile_specs)
}

refresh_system_font_cache() {
  run_cmd fc-cache -s
}

refresh_user_font_cache() {
  local cache_home="$LABWC_TARGET_HOME/.cache"
  local cache_dir="${cache_home}/fontconfig"
  local user_fonts_dir="$LABWC_TARGET_HOME/.local/share/fonts"
  local legacy_fonts_dir="$LABWC_TARGET_HOME/.fonts"
  local -a font_dirs=()

  if [[ -d "$user_fonts_dir" ]]; then
    font_dirs+=("$user_fonts_dir")
  fi
  if [[ -d "$legacy_fonts_dir" ]]; then
    font_dirs+=("$legacy_fonts_dir")
  fi

  run_cmd install -d -m 0700 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" "$cache_home" "$cache_dir"

  if ((${#font_dirs[@]} == 0)); then
    log_info "rendered $LABWC_TARGET_HOME/.config/fontconfig/fonts.conf; no user font directories under $user_fonts_dir or $legacy_fonts_dir, so only the system font cache was refreshed"
    return 0
  fi

  run_cmd runuser -u "$LABWC_TARGET_USER" -- env \
    HOME="$LABWC_TARGET_HOME" \
    XDG_CONFIG_HOME="$LABWC_TARGET_HOME/.config" \
    XDG_CACHE_HOME="$cache_home" \
    fc-cache -f "${font_dirs[@]}"
}

user_fontconfig_match() {
  local cache_home="$LABWC_TARGET_HOME/.cache"
  local pattern="$1"

  run_cmd runuser -u "$LABWC_TARGET_USER" -- env \
    HOME="$LABWC_TARGET_HOME" \
    XDG_CONFIG_HOME="$LABWC_TARGET_HOME/.config" \
    XDG_CACHE_HOME="$cache_home" \
    fc-match -f '%{family}\n' "$pattern"
}

validate_user_fontconfig() {
  local sans_match serif_match mono_match emoji_match

  sans_match="$(user_fontconfig_match 'sans-serif')"
  serif_match="$(user_fontconfig_match 'serif')"
  mono_match="$(user_fontconfig_match 'monospace')"
  emoji_match="$(user_fontconfig_match 'emoji')"

  [[ "$sans_match" == *"Noto Sans"* ]] || die "user fontconfig did not resolve sans-serif to Noto Sans: ${sans_match:-empty}"
  [[ "$serif_match" == *"Noto Serif"* ]] || die "user fontconfig did not resolve serif to Noto Serif: ${serif_match:-empty}"
  [[ "$mono_match" == *"Noto Sans Mono"* ]] || die "user fontconfig did not resolve monospace to Noto Sans Mono: ${mono_match:-empty}"
  [[ "$emoji_match" == *"Noto Color Emoji"* || "$emoji_match" == *"Symbola"* ]] || {
    die "user fontconfig did not resolve emoji to Noto Color Emoji or Symbola: ${emoji_match:-empty}"
  }

  log_info "validated target-user fontconfig aliases via fc-match"
}

remove_managed_wireguard_profiles() {
  local profile_name profile_label profile_flag
  while IFS='|' read -r profile_name profile_label profile_flag; do
    [[ -n "$profile_name" ]] || continue
    nmcli connection delete id "$profile_name" >/dev/null 2>&1 || true
  done < <(wireguard_profile_specs)
  remove_if_present "$(wireguard_import_dir)"
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

regreet_binary_path() {
  printf '%s\n' "/usr/local/bin/regreet"
}

regreet_config_path() {
  printf '%s\n' "/etc/greetd/regreet.toml"
}

regreet_css_path() {
  printf '%s\n' "/etc/greetd/regreet.css"
}

greeter_regreet_launcher_path() {
  printf '%s\n' "/usr/local/bin/labwc-greeter-regreet"
}

greeter_labwc_config_dir() {
  printf '%s\n' "/etc/labwc-greeter"
}

greeter_wallpaper_dir() {
  printf '%s\n' "/usr/local/share/labwc-greeter"
}

regreet_wallpaper_target_path() {
  printf '%s\n' "$(greeter_wallpaper_dir)/$(basename "$(regreet_wallpaper_source_path)")"
}

remove_regreet_support_files() {
  remove_if_present "$(regreet_binary_path)"
  remove_if_present "$(regreet_config_path)"
  remove_if_present "$(regreet_css_path)"
  remove_if_present "$(greeter_regreet_launcher_path)"
  remove_if_present "$(greeter_labwc_config_dir)"
  remove_if_present "$(greeter_wallpaper_dir)"
}

install_regreet_release() {
  local tmpdir tarball_path extracted_path actual_sha tar_listing
  local -a tar_entries=()

  validate_regreet_settings
  require_command curl
  require_command tar
  require_command sha256sum
  require_command mktemp

  tmpdir="$(mktemp -d)"
  trap 'rm -rf -- "$tmpdir"' RETURN
  tarball_path="$tmpdir/regreet.tar.gz"
  extracted_path="$tmpdir/regreet"

  log_info "installing regreet ${GITHUB_REGREET_TAG} (${GITHUB_REGREET_COMMIT_SHA})"
  retry_cmd 3 curl --fail --location --max-time 60 --silent --show-error -o "$tarball_path" "$GITHUB_REGREET_TARBALL"
  actual_sha="$(sha256sum "$tarball_path" | awk '{print $1}')"
  [[ "$actual_sha" == "$GITHUB_REGREET_TARBALL_SHA" ]] || {
    die "regreet tarball sha256 mismatch: expected ${GITHUB_REGREET_TARBALL_SHA}, got ${actual_sha}"
  }

  mapfile -t tar_entries < <(tar -tf "$tarball_path")
  ((${#tar_entries[@]} == 1)) || die "regreet tarball must contain exactly one file, found ${#tar_entries[@]}"
  [[ "${tar_entries[0]}" == "regreet" ]] || die "regreet tarball must contain a top-level 'regreet' file, found '${tar_entries[0]}'"
  tar_listing="$(tar -tvf "$tarball_path")"
  [[ "${tar_listing:0:1}" == "-" ]] || die "regreet tarball entry must be a regular file, found '${tar_listing%% *}'"

  run_cmd tar -xf "$tarball_path" -C "$tmpdir"
  [[ ! -L "$extracted_path" ]] || die "regreet tarball extracted a symlink, expected a regular file"
  [[ -f "$extracted_path" ]] || die "regreet tarball did not extract an executable file at '$extracted_path'"
  [[ -x "$extracted_path" ]] || die "regreet tarball did not extract an executable binary at '$extracted_path'"
  run_cmd install -D -m 0755 "$extracted_path" "$(regreet_binary_path)"
  "$(regreet_binary_path)" --version >/dev/null 2>&1 || die "installed regreet binary failed the --version self-test"
  trap - RETURN
  run_cmd rm -rf -- "$tmpdir"
}

install_regreet_support_dirs() {
  run_cmd install -d -m 0755 "$(greeter_labwc_config_dir)" "$(greeter_wallpaper_dir)"
}

install_regreet_wallpaper() {
  local wallpaper_source_path
  wallpaper_source_path="$(regreet_wallpaper_source_path)"
  run_cmd install -D -m 0644 "$wallpaper_source_path" "$(regreet_wallpaper_target_path)"
}

install_regreet_files() {
  install_regreet_release
  install_regreet_support_dirs
  install_regreet_wallpaper
  render_template_to_file "$(config_system_template_path "greetd/config.toml")" "/etc/greetd/config.toml" 0644
  render_template_to_file "$(config_system_template_path "greetd/regreet.toml")" "$(regreet_config_path)" 0644
  render_template_to_file "$(config_system_template_path "greetd/regreet.css")" "$(regreet_css_path)" 0644
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-greeter-regreet")" "$(greeter_regreet_launcher_path)" 0755
  render_template_to_file "$(config_system_template_path "labwc-greeter/autostart")" "$(greeter_labwc_config_dir)/autostart" 0755
  render_template_to_file "$(config_system_template_path "labwc-greeter/rc.xml")" "$(greeter_labwc_config_dir)/rc.xml" 0644
}

install_root_files() {
  validate_greetd_vt
  ensure_greeter_user
  ensure_greeter_runtime_dirs
  remove_regreet_support_files
  install_regreet_files
  render_template_to_file "$(config_system_template_path "usr/share/wayland-sessions/labwc.desktop")" "/usr/share/wayland-sessions/labwc.desktop" 0644
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-session-start")" "/usr/local/bin/labwc-session-start" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-session")" "/usr/local/bin/labwc-session" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-power-menu")" "/usr/local/bin/labwc-power-menu" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-screenshot-full")" "/usr/local/bin/labwc-screenshot-full" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-screenshot-region")" "/usr/local/bin/labwc-screenshot-region" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-record-toggle")" "/usr/local/bin/labwc-record-toggle" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-dpms")" "/usr/local/bin/labwc-dpms" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-refresh-outputs")" "/usr/local/bin/labwc-refresh-outputs" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-start-waybar")" "/usr/local/bin/labwc-start-waybar" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-lock")" "/usr/local/bin/labwc-lock" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-launcher-menu")" "/usr/local/bin/labwc-launcher-menu" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-module-menu")" "/usr/local/bin/labwc-module-menu" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-network-settings")" "/usr/local/bin/labwc-network-settings" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-vpnctl")" "/usr/local/bin/labwc-vpnctl" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-wireguard-import")" "/usr/local/bin/labwc-wireguard-import" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-player-status")" "/usr/local/bin/labwc-player-status" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/thunar-open-archive")" "/usr/local/bin/thunar-open-archive" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/thunar-create-archive")" "/usr/local/bin/thunar-create-archive" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/thunar-extract-here")" "/usr/local/bin/thunar-extract-here" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/thunar-open-terminal-here")" "/usr/local/bin/thunar-open-terminal-here" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-unlock-gpg-key")" "/usr/local/bin/labwc-unlock-gpg-key" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-workspacectl")" "/usr/local/bin/labwc-workspacectl" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-workspace-activate")" "/usr/local/bin/labwc-workspace-activate" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-workspace-send")" "/usr/local/bin/labwc-workspace-send" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-workspace-state")" "/usr/local/bin/labwc-workspace-state" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-workspace-status")" "/usr/local/bin/labwc-workspace-status" 0755
  render_template_to_file "$(config_system_template_path "etc/systemd/system/labwc-wireguard-import.service")" "/etc/systemd/system/labwc-wireguard-import.service" 0644
  render_template_to_file "$(config_system_template_path "etc/systemd/system/labwc-vpn-default-off.service")" "/etc/systemd/system/labwc-vpn-default-off.service" 0644
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
  run_cmd systemctl enable "$(wireguard_import_service_name)"
  run_cmd systemctl enable labwc-vpn-default-off.service
  if ! systemctl is-active --quiet NetworkManager.service >/dev/null 2>&1; then
    run_cmd systemctl start NetworkManager.service
  fi
  run_cmd systemctl enable switcheroo-control.service
  run_cmd systemctl enable udisks2.service
  run_cmd systemctl enable upower.service
  run_cmd systemctl restart polkit.service >/dev/null 2>&1 || true
}

enable_all_services() {
  install_root_files
  enable_system_services_only
  stage_wireguard_profiles
  enable_user_services
  refresh_system_font_cache
  refresh_user_font_cache
  validate_user_fontconfig
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
  remove_if_present "$LABWC_TARGET_HOME/.config/fontconfig"
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
  remove_if_present "/usr/local/bin/labwc-session-start"
  remove_if_present "/usr/local/bin/labwc-power-menu"
  remove_if_present "/usr/local/bin/labwc-screenshot-full"
  remove_if_present "/usr/local/bin/labwc-screenshot-region"
  remove_if_present "/usr/local/bin/labwc-record-toggle"
  remove_if_present "/usr/local/bin/labwc-dpms"
  remove_if_present "/usr/local/bin/labwc-refresh-outputs"
  remove_if_present "/usr/local/bin/labwc-start-waybar"
  remove_if_present "/usr/local/bin/labwc-lock"
  remove_if_present "/usr/local/bin/labwc-launcher-menu"
  remove_if_present "/usr/local/bin/labwc-module-menu"
  remove_if_present "/usr/local/bin/labwc-network-settings"
  remove_if_present "/usr/local/bin/labwc-vpnctl"
  remove_if_present "/usr/local/bin/labwc-wireguard-import"
  remove_if_present "/usr/local/bin/labwc-player-status"
  remove_if_present "$(greeter_regreet_launcher_path)"
  remove_if_present "/usr/local/bin/thunar-open-archive"
  remove_if_present "/usr/local/bin/thunar-create-archive"
  remove_if_present "/usr/local/bin/thunar-extract-here"
  remove_if_present "/usr/local/bin/thunar-open-terminal-here"
  remove_if_present "/usr/local/bin/labwc-unlock-gpg-key"
  remove_if_present "/usr/local/bin/labwc-workspacectl"
  remove_if_present "/usr/local/bin/labwc-workspace-activate"
  remove_if_present "/usr/local/bin/labwc-workspace-send"
  remove_if_present "/usr/local/bin/labwc-workspace-state"
  remove_if_present "/usr/local/bin/labwc-workspace-status"
  remove_if_present "$(regreet_binary_path)"
  remove_if_present "/usr/share/wayland-sessions/labwc.desktop"
  remove_if_present "/etc/greetd/config.toml"
  remove_if_present "$(regreet_config_path)"
  remove_if_present "$(regreet_css_path)"
  remove_if_present "$(greeter_labwc_config_dir)"
  remove_if_present "$(greeter_wallpaper_dir)"
  systemctl disable "$(wireguard_import_service_name)" >/dev/null 2>&1 || true
  systemctl disable labwc-vpn-default-off.service >/dev/null 2>&1 || true
  remove_if_present "/etc/systemd/system/labwc-wireguard-import.service"
  remove_if_present "/etc/systemd/system/labwc-vpn-default-off.service"
  remove_labwc_tweaks_install
  remove_keepsecret_install
  remove_managed_wireguard_profiles

  log_info "removing target user systemd user unit links"
  disable_target_user_unit pipewire.service
  disable_target_user_unit pipewire.socket
  disable_target_user_unit pipewire-pulse.service
  disable_target_user_unit pipewire-pulse.socket
  disable_target_user_unit wireplumber.service

  log_info "disabling greetd and restoring multi-user target"
  systemctl disable greetd.service >/dev/null 2>&1 || true
  systemctl set-default multi-user.target >/dev/null 2>&1 || true

  log_info "removing greeter cache and greeter user"
  remove_if_present "/var/lib/greetd/greeter"
  if getent passwd greeter >/dev/null 2>&1; then
    userdel greeter >/dev/null 2>&1 || true
  fi
}
