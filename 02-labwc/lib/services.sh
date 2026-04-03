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

greeter_access_groups() {
  local group_name
  for group_name in video render input audio; do
    getent group "$group_name" >/dev/null 2>&1 || continue
    printf '%s\n' "$group_name"
  done
}

ensure_greeter_access_groups() {
  local group_csv=""
  local group_name

  while IFS= read -r group_name; do
    [[ -n "$group_name" ]] || continue
    if [[ -n "$group_csv" ]]; then
      group_csv+=",${group_name}"
    else
      group_csv="$group_name"
    fi
  done < <(greeter_access_groups)

  [[ -n "$group_csv" ]] || return 0
  run_cmd usermod -a -G "$group_csv" greeter
}

ensure_greeter_runtime_dirs() {
  run_cmd install -d -m 0700 -o greeter -g greeter /var/lib/greetd/greeter
  run_cmd install -d -m 0700 -o greeter -g greeter /var/lib/greetd/greeter/.cache
  run_cmd install -d -m 0700 -o greeter -g greeter /var/lib/greetd/greeter/.config
  run_cmd install -d -m 0700 -o greeter -g greeter /var/lib/greetd/greeter/.local
  run_cmd install -d -m 0700 -o greeter -g greeter /var/lib/greetd/greeter/.local/state
  run_cmd install -d -m 0700 -o greeter -g greeter /var/lib/greetd/greeter/.local/share
  run_cmd install -d -m 0700 -o greeter -g greeter /var/lib/regreet
  run_cmd install -d -m 0750 -o greeter -g greeter "$(greeter_log_dir)"
  run_cmd install -D -m 0640 -o greeter -g greeter /dev/null "$(greeter_log_path)"
  run_cmd install -D -m 0640 -o greeter -g greeter /dev/null "$(greeter_session_log_path)"
}

validate_greetd_vt() {
  [[ "${LABWC_GREETD_VT:-}" =~ ^[1-9][0-9]*$ ]] || die "LABWC_GREETD_VT must be a positive integer, found '${LABWC_GREETD_VT:-}'"
}

validate_regreet_settings() {
  case "${LABWC_INSTALL_METHOD:-}" in
    source)
      require_https_url "REGREET_GIT_URL" "${REGREET_GIT_URL:-}"
      require_commit_sha "${REGREET_COMMIT_SHA:-}"
      [[ "${REGREET_RUST_TOOLCHAIN:-}" =~ ^nightly-[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || {
        die "REGREET_RUST_TOOLCHAIN must be a dated nightly, found '${REGREET_RUST_TOOLCHAIN:-}'"
      }
      ;;
    artifact)
      require_https_url "REGREET_TARBALL_URL" "${REGREET_TARBALL_URL:-}"
      require_sha256_hex "$(normalize_sha256_value "${REGREET_TARBALL_SHA:-}")"
      require_safe_token "REGREET_COMMIT_TAG" "${REGREET_COMMIT_TAG:-}"
      require_commit_sha "${REGREET_COMMIT_SHA:-}"
      ;;
    *)
      die "LABWC_INSTALL_METHOD must be 'source' or 'artifact', found '${LABWC_INSTALL_METHOD:-}'"
      ;;
  esac
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

target_user_env_path() {
  printf '%s\n' "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
}

run_target_user_command() {
  local -a env_args=(
    "HOME=$LABWC_TARGET_HOME"
    "USER=$LABWC_TARGET_USER"
    "LOGNAME=$LABWC_TARGET_USER"
    "PATH=$(target_user_env_path)"
    "XDG_CONFIG_HOME=$LABWC_TARGET_HOME/.config"
    "XDG_CACHE_HOME=$LABWC_TARGET_HOME/.cache"
    "XDG_DATA_HOME=$LABWC_TARGET_HOME/.local/share"
    "XDG_STATE_HOME=$LABWC_TARGET_HOME/.local/state"
    "TMPDIR=/tmp"
    "TMP=/tmp"
    "TEMP=/tmp"
  )

  while (($#)); do
    case "$1" in
      *=*)
        env_args+=("$1")
        shift
        ;;
      --)
        shift
        break
        ;;
      *)
        break
        ;;
    esac
  done

  (($# > 0)) || die "run_target_user_command requires a command"
  run_cmd runuser -u "$LABWC_TARGET_USER" -- env -i "${env_args[@]}" "$@"
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
  local import_dir profile_name rendered_path
  import_dir="$(wireguard_import_dir)"

  if [[ -n "${WIREGUARD_PRIV_KEY:-}" ]] && declare -F validate_wireguard_private_key >/dev/null 2>&1; then
    validate_wireguard_private_key "$WIREGUARD_PRIV_KEY" >/dev/null 2>&1 || die "WIREGUARD_PRIV_KEY is invalid"
  fi

  run_cmd install -d -m 0700 "$import_dir"
  run_cmd find "$import_dir" -maxdepth 1 -type f -name '*.conf' -delete

  while IFS='|' read -r profile_name _ _; do
    [[ -n "$profile_name" ]] || continue
    rendered_path="${import_dir}/${profile_name}.conf"
    render_wireguard_profile_file "$profile_name" "$rendered_path"
  done < <(wireguard_profile_specs)

  if [[ -z "${WIREGUARD_PRIV_KEY:-}" ]]; then
    log_info "No WireGuard private key provided. You must manually enter the private key in the installed generated WireGuard configs if you want VPN to work."
  fi
}

refresh_system_font_cache() {
  run_cmd fc-cache -s
}

refresh_user_font_cache() {
  local cache_home="$LABWC_TARGET_HOME/.cache"
  local cache_dir="${cache_home}/fontconfig"
  local user_fonts_dir="$LABWC_TARGET_HOME/.local/share/fonts"
  local -a font_dirs=()

  if [[ -d "$user_fonts_dir" ]]; then
    font_dirs+=("$user_fonts_dir")
  fi

  run_cmd install -d -m 0700 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_GROUP" "$cache_home" "$cache_dir"

  if ((${#font_dirs[@]} == 0)); then
    log_info "rendered $LABWC_TARGET_HOME/.config/fontconfig/fonts.conf; no user font directory exists under $user_fonts_dir, so only the system font cache was refreshed"
    return 0
  fi

  run_target_user_command \
    "XDG_CACHE_HOME=$cache_home" \
    -- fc-cache -f "${font_dirs[@]}"
}

user_fontconfig_match() {
  local cache_home="$LABWC_TARGET_HOME/.cache"
  local pattern="$1"

  run_target_user_command \
    "XDG_CACHE_HOME=$cache_home" \
    -- fc-match -f '%{family}\n' "$pattern"
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
  local profile_name _
  while IFS='|' read -r profile_name _; do
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
  run_target_user_command \
    "GNUPGHOME=$LABWC_TARGET_HOME/.gnupg" \
    "KWALLET_SESSION_GPG_PASSWD=$gpg_passphrase" \
    "LABWC_TARGET_USER=$LABWC_TARGET_USER" \
    "LABWC_GPG_KEY_REALNAME=${LABWC_GPG_KEY_REALNAME:-}" \
    "LABWC_GPG_KEY_EMAIL=${LABWC_GPG_KEY_EMAIL:-}" \
    "LABWC_GPG_KEY_EXPIRE=${LABWC_GPG_KEY_EXPIRE:-2y}" \
    -- bash "$SCRIPT_DIR/libexec/ensure-gpg-key.sh"
  stage_target_user_gpg_secret_seed "$gpg_passphrase"
}

stage_target_user_gpg_secret_seed() {
  local gpg_passphrase="$1"
  local state_dir="$LABWC_TARGET_HOME/.local/state/labwc-session"
  local seed_path="$state_dir/kwallet-session-gpg-passphrase.seed"
  [[ -n "$gpg_passphrase" ]] || return 0
  run_cmd install -d -m 0700 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_GROUP" "$state_dir"
  run_cmd install -D -m 0600 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_GROUP" /dev/null "$seed_path"
  printf '%s' "$gpg_passphrase" >"$seed_path"
  run_cmd chown "$LABWC_TARGET_USER:$LABWC_TARGET_GROUP" "$seed_path"
  run_cmd chmod 0600 "$seed_path"
}

regreet_binary_path() {
  printf '%s\n' "/usr/local/bin/regreet"
}

regreet_provenance_path() {
  printf '%s\n' "/var/lib/labwc-session/regreet-build.env"
}

regreet_rust_state_root() {
  printf '%s\n' "/var/lib/labwc-session/rust"
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

greeter_session_wrapper_path() {
  printf '%s\n' "/usr/local/bin/labwc-greeter-session"
}

greeter_labwc_config_dir() {
  printf '%s\n' "/etc/labwc-greeter"
}

greeter_wallpaper_dir() {
  printf '%s\n' "/usr/local/share/labwc-greeter"
}

greeter_log_dir() {
  printf '%s\n' "/var/log/regreet"
}

greeter_log_path() {
  printf '%s\n' "$(greeter_log_dir)/log"
}

greeter_session_log_path() {
  printf '%s\n' "$(greeter_log_dir)/greeter-session.log"
}

regreet_wallpaper_target_path() {
  printf '%s\n' "$(greeter_wallpaper_dir)/$(basename "$(regreet_wallpaper_source_path)")"
}

remove_regreet_runtime_files() {
  remove_if_present "$(regreet_config_path)"
  remove_if_present "$(regreet_css_path)"
  remove_if_present "$(greeter_regreet_launcher_path)"
  remove_if_present "$(greeter_session_wrapper_path)"
  remove_if_present "$(greeter_labwc_config_dir)"
  remove_if_present "$(greeter_wallpaper_dir)"
}

install_regreet_binary() {
  local work_root repo_dir target_dir rust_state_root provenance log_path rust_flags

  validate_regreet_settings
  ensure_source_state_dir
  log_path="$(build_log_path "regreet-build")"
  rust_state_root="$(regreet_rust_state_root)"
  ensure_rustup_toolchain "$rust_state_root" "$REGREET_RUST_TOOLCHAIN" "$log_path"
  work_root="$(fetch_source_checkout "regreet" "$REGREET_GIT_URL" "$REGREET_COMMIT_SHA" "$log_path")"
  repo_dir="$work_root/source"
  target_dir="$work_root/target"
  rust_flags="$(native_rustflags)"

  trap 'cleanup_source_checkout "$work_root"' RETURN

  log_info "building regreet from ${REGREET_COMMIT_SHA} with ${REGREET_RUST_TOOLCHAIN}"
  run_logged_command "$log_path" \
    env PATH="$(rust_toolchain_bin_dir "$rust_state_root"):$PATH" \
      CC="$(llvm_clang_bin)" \
      CXX="$(llvm_clangxx_bin)" \
      RUSTFLAGS="$rust_flags" \
      CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 \
      GREETD_CONFIG_DIR=/etc/greetd \
      STATE_DIR=/var/lib/regreet \
      LOG_DIR=/var/log/regreet \
      REBOOT_CMD="loginctl reboot" \
      POWEROFF_CMD="loginctl poweroff" \
      CARGO_TARGET_DIR="$target_dir" \
      cargo build --release --features gtk4_8 --manifest-path "$repo_dir/Cargo.toml"

  run_cmd install -D -m 0755 "$target_dir/release/regreet" "$(regreet_binary_path)"
  assert_binary_dependencies "$(regreet_binary_path)" "regreet"
  "$(regreet_binary_path)" --version >/dev/null 2>&1 || die "installed regreet binary failed the --version self-test"

  provenance="$(cat <<EOF
REGREET_GIT_URL="$REGREET_GIT_URL"
REGREET_COMMIT_SHA="$REGREET_COMMIT_SHA"
REGREET_INSTALL_METHOD="source"
REGREET_RUST_TOOLCHAIN="$REGREET_RUST_TOOLCHAIN"
REGREET_RUSTFLAGS="$rust_flags"
REGREET_RUSTC_VERSION="$(rust_version_output "$rust_state_root" "$REGREET_RUST_TOOLCHAIN")"
REGREET_CARGO_VERSION="$(cargo_version_output "$rust_state_root" "$REGREET_RUST_TOOLCHAIN")"
REGREET_BUILD_LOG="$log_path"
REGREET_INSTALLED_AT_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
EOF
)"
  write_source_provenance "$(regreet_provenance_path)" "$provenance"

  trap - RETURN
  cleanup_source_checkout "$work_root"
}

install_regreet_artifact() {
  local work_root tarball_path stage_root provenance log_path

  validate_regreet_settings
  ensure_source_state_dir
  log_path="$(build_log_path "regreet-artifact-install")"
  work_root="$(download_release_tarball "regreet" "$REGREET_TARBALL_URL" "$REGREET_TARBALL_SHA" "$log_path")"
  tarball_path="$work_root/archive.tar.gz"
  stage_root="$work_root/stage"

  trap 'cleanup_source_checkout "$work_root"' RETURN

  extract_release_tarball "$tarball_path" "$stage_root"
  require_file "$stage_root/regreet"
  assert_binary_dependencies "$stage_root/regreet" "regreet artifact"
  run_cmd install -D -m 0755 "$stage_root/regreet" "$(regreet_binary_path)"
  assert_binary_dependencies "$(regreet_binary_path)" "regreet"
  "$(regreet_binary_path)" --version >/dev/null 2>&1 || die "installed regreet artifact failed the --version self-test"

  provenance="$(cat <<EOF
REGREET_INSTALL_METHOD="artifact"
REGREET_TARBALL_URL="$REGREET_TARBALL_URL"
REGREET_TARBALL_SHA="$(normalize_sha256_value "$REGREET_TARBALL_SHA")"
REGREET_COMMIT_TAG="$REGREET_COMMIT_TAG"
REGREET_COMMIT_SHA="$REGREET_COMMIT_SHA"
REGREET_BUILD_LOG="$log_path"
REGREET_INSTALLED_AT_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
EOF
)"
  write_source_provenance "$(regreet_provenance_path)" "$provenance"

  trap - RETURN
  cleanup_source_checkout "$work_root"
}

install_regreet_support_dirs() {
  run_cmd install -d -m 0755 "$(greeter_labwc_config_dir)" "$(greeter_wallpaper_dir)"
}

install_regreet_wallpaper() {
  local wallpaper_source_path
  wallpaper_source_path="$(regreet_wallpaper_source_path)"
  run_cmd install -D -m 0644 "$wallpaper_source_path" "$(regreet_wallpaper_target_path)"
}

install_regreet_runtime_files() {
  require_file "$(regreet_binary_path)"
  install_regreet_support_dirs
  install_regreet_wallpaper
  render_template_to_file "$(config_system_template_path "greetd/config.toml")" "/etc/greetd/config.toml" 0644
  render_template_to_file "$(config_system_template_path "greetd/regreet.toml")" "$(regreet_config_path)" 0644
  render_template_to_file "$(config_system_template_path "greetd/regreet.css")" "$(regreet_css_path)" 0644
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-greeter-session")" "$(greeter_session_wrapper_path)" 0755
  render_template_to_file "$(config_system_template_path "usr/local/bin/labwc-greeter-regreet")" "$(greeter_regreet_launcher_path)" 0755
  render_template_to_file "$(config_system_template_path "labwc-greeter/autostart")" "$(greeter_labwc_config_dir)/autostart" 0755
  render_template_to_file "$(config_system_template_path "labwc-greeter/rc.xml")" "$(greeter_labwc_config_dir)/rc.xml" 0644
}

install_root_files() {
  validate_greetd_vt
  ensure_greeter_user
  ensure_greeter_access_groups
  ensure_greeter_runtime_dirs
  render_template_to_file "$(config_system_template_path "pam.d/greetd")" "/etc/pam.d/greetd" 0644
  render_template_to_file "$(config_system_template_path "pam.d/greetd-greeter")" "/etc/pam.d/greetd-greeter" 0644
  remove_regreet_runtime_files
  install_regreet_runtime_files
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
  run_cmd install -d -m 0755 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_GROUP" "$wants_dir"
  run_cmd ln -sfn "$unit_path" "$wants_dir/$unit_name"
  run_cmd chown -h "$LABWC_TARGET_USER:$LABWC_TARGET_GROUP" "$wants_dir/$unit_name"
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
  systemctl reset-failed greetd.service >/dev/null 2>&1 || true
  run_cmd systemctl enable NetworkManager.service
  if systemctl cat NetworkManager-dispatcher.service >/dev/null 2>&1; then
    run_cmd systemctl enable NetworkManager-dispatcher.service
  fi
  run_cmd systemctl enable "$(wireguard_import_service_name)"
  run_cmd systemctl enable labwc-vpn-default-off.service
  if ! systemctl is-active --quiet NetworkManager.service >/dev/null 2>&1; then
    run_cmd systemctl start NetworkManager.service
  fi
  run_cmd systemctl enable switcheroo-control.service
  run_cmd systemctl enable udisks2.service
  run_cmd systemctl enable upower.service
  if systemctl cat bluetooth.service >/dev/null 2>&1; then
    run_cmd systemctl enable bluetooth.service
    if ! systemctl is-active --quiet bluetooth.service >/dev/null 2>&1; then
      run_cmd systemctl start bluetooth.service
    fi
  fi
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
  remove_if_present "$LABWC_TARGET_HOME/.config/wireplumber"
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
  remove_regreet_runtime_files
  remove_if_present "$(regreet_binary_path)"
  remove_if_present "$(regreet_provenance_path)"
  remove_if_present "/usr/share/wayland-sessions/labwc.desktop"
  remove_if_present "/etc/pam.d/greetd"
  remove_if_present "/etc/pam.d/greetd-greeter"
  remove_if_present "/etc/greetd/config.toml"
  systemctl disable "$(wireguard_import_service_name)" >/dev/null 2>&1 || true
  systemctl disable labwc-vpn-default-off.service >/dev/null 2>&1 || true
  remove_if_present "/etc/systemd/system/labwc-wireguard-import.service"
  remove_if_present "/etc/systemd/system/labwc-vpn-default-off.service"
  remove_kirigami_runtime_install
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
  remove_if_present "/var/lib/regreet"
  remove_if_present "/var/log/regreet"
  remove_if_present "$(regreet_rust_state_root)"
  if getent passwd greeter >/dev/null 2>&1; then
    userdel greeter >/dev/null 2>&1 || true
  fi
}
