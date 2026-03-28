#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

state="${1:-}"
[[ "$state" == "on" || "$state" == "off" ]] || exit 1

internal_output="@INTERNAL_OUTPUT@"
external_output="@EXTERNAL_OUTPUT@"

for output in "$internal_output" "$external_output"; do
  [[ -n "$output" ]] || continue
  wlr-randr --output "$output" "--$state" || true
done
