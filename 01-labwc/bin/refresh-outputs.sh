#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

runtime_env="@RUNTIME_ENV_PATH@"
repo_env="@REPO_ENV_PATH@"
state_dir="$HOME/.config/debian-labwc"
marker_file="$state_dir/.outputs-refined"

[[ -r "$runtime_env" ]] || exit 0

# shellcheck disable=SC1090
source "$runtime_env"

mkdir -p "$state_dir"

[[ -n "${LABWC_EXTERNAL_OUTPUT:-}" ]] || {
  touch "$marker_file"
  exit 0
}

current_output=""
current_mode=""
current_hz=""
external_mode="${LABWC_EXTERNAL_MODE:-1920x1080}"
external_hz="${LABWC_EXTERNAL_HZ:-60}"
external_120="no"

while IFS= read -r line; do
  if [[ "$line" != ' '* ]]; then
    current_output="${line%% *}"
    continue
  fi
  if [[ "$current_output" != "${LABWC_EXTERNAL_OUTPUT:-}" ]]; then
    continue
  fi
  if [[ "$line" == *"(preferred"* || "$line" == *"(current"* ]]; then
    current_mode="$(printf '%s\n' "$line" | awk '{print $1}')"
    current_hz="$(printf '%s\n' "$line" | awk '{print $3}' | cut -d. -f1)"
  fi
  if [[ "$line" == *"1920x1080"* && "$line" == *"120."* ]]; then
    external_mode="1920x1080"
    external_hz="120"
    external_120="yes"
  fi
done < <(wlr-randr 2>/dev/null || true)

if [[ "$external_120" != "yes" && -n "$current_mode" && -n "$current_hz" ]]; then
  external_mode="$current_mode"
  external_hz="$current_hz"
fi

tmp_file="$(mktemp)"
awk \
  -v ext_mode="$external_mode" \
  -v ext_hz="$external_hz" \
  -v ext120="$external_120" \
  '
    /^LABWC_EXTERNAL_MODE=/ {$0 = "LABWC_EXTERNAL_MODE=\"" ext_mode "\""}
    /^LABWC_EXTERNAL_HZ=/ {$0 = "LABWC_EXTERNAL_HZ=\"" ext_hz "\""}
    /^LABWC_EXTERNAL_120HZ_AVAILABLE=/ {$0 = "LABWC_EXTERNAL_120HZ_AVAILABLE=\"" ext120 "\""}
    {print}
  ' "$runtime_env" >"$tmp_file"
mv -- "$tmp_file" "$runtime_env"

if [[ -w "$repo_env" ]]; then
  tmp_file="$(mktemp)"
  awk \
    -v ext_mode="$external_mode" \
    -v ext_hz="$external_hz" \
    -v ext120="$external_120" \
    '
      /^LABWC_EXTERNAL_MODE=/ {$0 = "LABWC_EXTERNAL_MODE=\"" ext_mode "\""}
      /^LABWC_EXTERNAL_HZ=/ {$0 = "LABWC_EXTERNAL_HZ=\"" ext_hz "\""}
      /^LABWC_EXTERNAL_120HZ_AVAILABLE=/ {$0 = "LABWC_EXTERNAL_120HZ_AVAILABLE=\"" ext120 "\""}
      {print}
    ' "$repo_env" >"$tmp_file"
  mv -- "$tmp_file" "$repo_env"
fi

if [[ -n "${LABWC_INTERNAL_OUTPUT:-}" ]]; then
  cat >"$HOME/.config/kanshi/config" <<EOF
profile internal {
  output "$LABWC_INTERNAL_OUTPUT" mode ${LABWC_INTERNAL_MODE}@${LABWC_INTERNAL_HZ}Hz position 0,0 enable
}

profile external {
  output "$LABWC_EXTERNAL_OUTPUT" mode ${external_mode}@${external_hz}Hz position 0,0 enable
  output "$LABWC_INTERNAL_OUTPUT" disable
}

profile dual {
  output "$LABWC_EXTERNAL_OUTPUT" mode ${external_mode}@${external_hz}Hz position 0,0 enable
  output "$LABWC_INTERNAL_OUTPUT" mode ${LABWC_INTERNAL_MODE}@${LABWC_INTERNAL_HZ}Hz position 1920,0 enable
}
EOF
else
  cat >"$HOME/.config/kanshi/config" <<EOF
profile external {
  output "$LABWC_EXTERNAL_OUTPUT" mode ${external_mode}@${external_hz}Hz position 0,0 enable
}
EOF
fi

pkill -x kanshi >/dev/null 2>&1 || true
nohup kanshi >/dev/null 2>&1 &
touch "$marker_file"
