#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

state="${1:-}"
[[ "$state" == "on" || "$state" == "off" ]] || exit 1

if [[ -r "@RUNTIME_ENV_PATH@" ]]; then
  # shellcheck disable=SC1090,SC1091
  source "@RUNTIME_ENV_PATH@"
fi

for output in "${LABWC_INTERNAL_OUTPUT:-}" "${LABWC_EXTERNAL_OUTPUT:-}"; do
  [[ -n "$output" ]] || continue
  wlr-randr --output "$output" "--$state" || true
done
