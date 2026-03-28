#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

state_dir="$HOME/.config/debian-labwc"
marker_file="$state_dir/.outputs-refined"
internal_output="@INTERNAL_OUTPUT@"
external_output="@EXTERNAL_OUTPUT@"
internal_mode="@INTERNAL_MODE@"
internal_hz="@INTERNAL_HZ@"
external_mode_default="@EXTERNAL_MODE@"
external_hz_default="@EXTERNAL_HZ@"

mkdir -p "$state_dir"

[[ -n "$external_output" ]] || {
  touch "$marker_file"
  exit 0
}

current_output=""
current_mode=""
current_hz=""
external_mode="${external_mode_default:-1920x1080}"
external_hz="${external_hz_default:-60}"
external_120="no"

while IFS= read -r line; do
  if [[ "$line" != ' '* ]]; then
    current_output="${line%% *}"
    continue
  fi
  if [[ "$current_output" != "$external_output" ]]; then
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

if [[ -n "$internal_output" ]]; then
  cat >"$HOME/.config/kanshi/config" <<EOF
profile internal {
  output "$internal_output" mode ${internal_mode}@${internal_hz}Hz position 0,0 enable
}

profile external {
  output "$external_output" mode ${external_mode}@${external_hz}Hz position 0,0 enable
  output "$internal_output" disable
}

profile dual {
  output "$external_output" mode ${external_mode}@${external_hz}Hz position 0,0 enable
  output "$internal_output" mode ${internal_mode}@${internal_hz}Hz position 1920,0 enable
}
EOF
else
  cat >"$HOME/.config/kanshi/config" <<EOF
profile external {
  output "$external_output" mode ${external_mode}@${external_hz}Hz position 0,0 enable
}
EOF
fi

pkill -x kanshi >/dev/null 2>&1 || true
nohup kanshi >/dev/null 2>&1 &
touch "$marker_file"
