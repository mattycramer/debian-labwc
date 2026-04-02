#!/usr/bin/env bash

config_home_template_path() {
  printf '%s/config/home/%s\n' "$SCRIPT_DIR" "$1"
}

config_system_template_path() {
  printf '%s/config/system/%s\n' "$SCRIPT_DIR" "$1"
}

template_lock_wallpaper_name() {
  if declare -F lock_wallpaper_source_path >/dev/null 2>&1; then
    basename "$(lock_wallpaper_source_path)"
    return 0
  fi
  printf '%s\n' ""
}

render_template_content() {
  local template_path="$1"
  local background_wallpaper_path=""
  local lock_wallpaper_path=""
  local lock_wallpaper_name=""
  local regreet_background_path=""
  local intel_media_env=""
  local updates_script="$LABWC_TARGET_HOME/.config/waybar/scripts/pending-updates.sh"
  local upgrade_script="$LABWC_TARGET_HOME/.config/waybar/scripts/run-upgrades.sh"
  local gpu_launch_script="$LABWC_TARGET_HOME/.config/waybar/scripts/gpu-launch.sh"
  local kanshi_internal_profile="${KANSHI_INTERNAL_PROFILE:-}"
  local kanshi_external_clause="${KANSHI_EXTERNAL_CLAUSE:-}"

  [[ -f "$template_path" ]] || die "missing config template: $template_path"

  if [[ -d "$LABWC_TARGET_HOME/.local/share/labwc-session" || -d "$SCRIPT_DIR/wallpaper" ]]; then
    if declare -F background_wallpaper_target_path >/dev/null 2>&1; then
      background_wallpaper_path="$(background_wallpaper_target_path)"
    fi
    if declare -F lock_wallpaper_target_path >/dev/null 2>&1; then
      lock_wallpaper_path="$(lock_wallpaper_target_path)"
    fi
    lock_wallpaper_name="$(template_lock_wallpaper_name)"
  fi
  if declare -F regreet_wallpaper_target_path >/dev/null 2>&1; then
    regreet_background_path="$(regreet_wallpaper_target_path)"
  fi
  if [[ "${LABWC_HAS_INTEL_GPU:-no}" == "yes" ]]; then
    intel_media_env="$(cat <<'EOF'
LIBVA_DRIVER_NAME=iHD
LIBVA_DRI_DRIVER_NAME=iHD
EOF
)"
  fi

  env \
    TEMPLATE_TARGET_HOME="$LABWC_TARGET_HOME" \
    TEMPLATE_TARGET_USER="$LABWC_TARGET_USER" \
    TEMPLATE_XCURSOR_THEME="${LABWC_XCURSOR_THEME:-}" \
    TEMPLATE_XCURSOR_SIZE="${LABWC_XCURSOR_SIZE:-}" \
    TEMPLATE_FOLLOW_MOUSE="${LABWC_FOLLOW_MOUSE:-}" \
    TEMPLATE_RAISE_ON_FOCUS="${LABWC_RAISE_ON_FOCUS:-}" \
    TEMPLATE_FOCUS_DELAY_MS="${LABWC_FOCUS_DELAY_MS:-}" \
    TEMPLATE_DOUBLECLICK_TIME_MS="${LABWC_DOUBLECLICK_TIME_MS:-}" \
    TEMPLATE_NATURAL_SCROLL="${LABWC_NATURAL_SCROLL:-}" \
    TEMPLATE_TERMINAL="${LABWC_TERMINAL:-}" \
    TEMPLATE_LAUNCHER_CMD="${LABWC_LAUNCHER_CMD:-}" \
    TEMPLATE_BACKGROUND_WALLPAPER_PATH="$background_wallpaper_path" \
    TEMPLATE_LOCK_WALLPAPER_PATH="$lock_wallpaper_path" \
    TEMPLATE_LOCK_WALLPAPER_NAME="$lock_wallpaper_name" \
    TEMPLATE_REGREET_BACKGROUND_PATH="$regreet_background_path" \
    TEMPLATE_WALLPAPER_MODE="${LABWC_WALLPAPER_MODE:-}" \
    TEMPLATE_IDLE_LOCK_SECONDS="${LABWC_IDLE_LOCK_SECONDS:-}" \
    TEMPLATE_IDLE_DPMS_SECONDS="${LABWC_IDLE_DPMS_SECONDS:-}" \
    TEMPLATE_KWALLET_SESSION_GPG_CACHE_TTL_SEC="${KWALLET_SESSION_GPG_CACHE_TTL_SEC:-}" \
    TEMPLATE_UPDATES_SCRIPT="$updates_script" \
    TEMPLATE_UPGRADE_SCRIPT="$upgrade_script" \
    TEMPLATE_GPU_LAUNCH_SCRIPT="$gpu_launch_script" \
    TEMPLATE_KANSHI_INTERNAL_PROFILE="$kanshi_internal_profile" \
    TEMPLATE_KANSHI_EXTERNAL_CLAUSE="$kanshi_external_clause" \
    TEMPLATE_INTEL_MEDIA_ENV="$intel_media_env" \
    TEMPLATE_GREETD_VT="${LABWC_GREETD_VT:-}" \
    TEMPLATE_SESSION_WRAPPER="/usr/local/bin/labwc-session" \
    TEMPLATE_WIREGUARD_PRIV_KEY="${WIREGUARD_PRIV_KEY:-}" \
    TEMPLATE_INTERNAL_OUTPUT="${LABWC_INTERNAL_OUTPUT:-}" \
    TEMPLATE_EXTERNAL_OUTPUT="${LABWC_EXTERNAL_OUTPUT:-}" \
    TEMPLATE_INTERNAL_MODE="${LABWC_INTERNAL_MODE:-}" \
    TEMPLATE_EXTERNAL_MODE="${LABWC_EXTERNAL_MODE:-}" \
    TEMPLATE_INTERNAL_HZ="${LABWC_INTERNAL_HZ:-}" \
    TEMPLATE_EXTERNAL_HZ="${LABWC_EXTERNAL_HZ:-}" \
    python3 - "$template_path" <<'PY'
import os
import re
import sys
from pathlib import Path

template_path = Path(sys.argv[1])
content = template_path.read_text()

replacements = {
    "@TARGET_HOME@": os.environ.get("TEMPLATE_TARGET_HOME", ""),
    "@TARGET_USER@": os.environ.get("TEMPLATE_TARGET_USER", ""),
    "@XCURSOR_THEME@": os.environ.get("TEMPLATE_XCURSOR_THEME", ""),
    "@XCURSOR_SIZE@": os.environ.get("TEMPLATE_XCURSOR_SIZE", ""),
    "@FOLLOW_MOUSE@": os.environ.get("TEMPLATE_FOLLOW_MOUSE", ""),
    "@RAISE_ON_FOCUS@": os.environ.get("TEMPLATE_RAISE_ON_FOCUS", ""),
    "@FOCUS_DELAY_MS@": os.environ.get("TEMPLATE_FOCUS_DELAY_MS", ""),
    "@DOUBLECLICK_TIME_MS@": os.environ.get("TEMPLATE_DOUBLECLICK_TIME_MS", ""),
    "@NATURAL_SCROLL@": os.environ.get("TEMPLATE_NATURAL_SCROLL", ""),
    "@TERMINAL@": os.environ.get("TEMPLATE_TERMINAL", ""),
    "@LAUNCHER_CMD@": os.environ.get("TEMPLATE_LAUNCHER_CMD", ""),
    "@BACKGROUND_WALLPAPER_PATH@": os.environ.get("TEMPLATE_BACKGROUND_WALLPAPER_PATH", ""),
    "@LOCK_WALLPAPER_PATH@": os.environ.get("TEMPLATE_LOCK_WALLPAPER_PATH", ""),
    "@LOCK_WALLPAPER_NAME@": os.environ.get("TEMPLATE_LOCK_WALLPAPER_NAME", ""),
    "@REGREET_BACKGROUND_PATH@": os.environ.get("TEMPLATE_REGREET_BACKGROUND_PATH", ""),
    "@WALLPAPER_MODE@": os.environ.get("TEMPLATE_WALLPAPER_MODE", ""),
    "@IDLE_LOCK_SECONDS@": os.environ.get("TEMPLATE_IDLE_LOCK_SECONDS", ""),
    "@IDLE_DPMS_SECONDS@": os.environ.get("TEMPLATE_IDLE_DPMS_SECONDS", ""),
    "@KWALLET_SESSION_GPG_CACHE_TTL_SEC@": os.environ.get("TEMPLATE_KWALLET_SESSION_GPG_CACHE_TTL_SEC", ""),
    "@UPDATES_SCRIPT@": os.environ.get("TEMPLATE_UPDATES_SCRIPT", ""),
    "@UPGRADE_SCRIPT@": os.environ.get("TEMPLATE_UPGRADE_SCRIPT", ""),
    "@GPU_LAUNCH_SCRIPT@": os.environ.get("TEMPLATE_GPU_LAUNCH_SCRIPT", ""),
    "@KANSHI_INTERNAL_PROFILE@": os.environ.get("TEMPLATE_KANSHI_INTERNAL_PROFILE", ""),
    "@KANSHI_EXTERNAL_CLAUSE@": os.environ.get("TEMPLATE_KANSHI_EXTERNAL_CLAUSE", ""),
    "@INTEL_MEDIA_ENV@": os.environ.get("TEMPLATE_INTEL_MEDIA_ENV", ""),
    "@GREETD_VT@": os.environ.get("TEMPLATE_GREETD_VT", ""),
    "@SESSION_WRAPPER@": os.environ.get("TEMPLATE_SESSION_WRAPPER", ""),
    "@WIREGUARD_PRIV_KEY@": os.environ.get("TEMPLATE_WIREGUARD_PRIV_KEY", ""),
    "@INTERNAL_OUTPUT@": os.environ.get("TEMPLATE_INTERNAL_OUTPUT", ""),
    "@EXTERNAL_OUTPUT@": os.environ.get("TEMPLATE_EXTERNAL_OUTPUT", ""),
    "@INTERNAL_MODE@": os.environ.get("TEMPLATE_INTERNAL_MODE", ""),
    "@EXTERNAL_MODE@": os.environ.get("TEMPLATE_EXTERNAL_MODE", ""),
    "@INTERNAL_HZ@": os.environ.get("TEMPLATE_INTERNAL_HZ", ""),
    "@EXTERNAL_HZ@": os.environ.get("TEMPLATE_EXTERNAL_HZ", ""),
}

literal_replacements = {
    "__DEFAULT_AUDIO_SINK__": "@DEFAULT_AUDIO_SINK@",
}
allowed_literals = {"@DEFAULT_AUDIO_SINK@"}

for placeholder, value in replacements.items():
    content = content.replace(placeholder, value)

for literal, value in literal_replacements.items():
    content = content.replace(literal, value)

unresolved = sorted(
    {
        token
        for token in re.findall(r"@[A-Z0-9_]+@", content)
        if token not in allowed_literals
    }
)
if unresolved:
    raise SystemExit(
        f"Unresolved placeholders in template {template_path}: {', '.join(unresolved)}"
    )

sys.stdout.write(content)
PY
}
