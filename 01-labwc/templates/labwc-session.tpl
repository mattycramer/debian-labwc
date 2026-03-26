#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=wlroots
export XDG_SESSION_DESKTOP=labwc
export DESKTOP_SESSION=labwc

if [[ -r "@RUNTIME_ENV_PATH@" ]]; then
  # shellcheck disable=SC1090
  source "@RUNTIME_ENV_PATH@"
fi

exec labwc
