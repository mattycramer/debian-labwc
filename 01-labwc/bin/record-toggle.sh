#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

pid_file="${XDG_RUNTIME_DIR:-/tmp}/debian-labwc-wf-recorder.pid"
output_dir="$HOME/Videos"
mkdir -p "$output_dir"

if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
  kill "$(cat "$pid_file")"
  rm -f -- "$pid_file"
  exit 0
fi

output_file="$output_dir/recording-$(date +%Y%m%d-%H%M%S).mkv"
wf-recorder -g "$(slurp)" -f "$output_file" >/dev/null 2>&1 &
printf '%s\n' "$!" >"$pid_file"
