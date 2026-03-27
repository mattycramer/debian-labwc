#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=labwc:wlroots
export XDG_SESSION_DESKTOP=labwc
export DESKTOP_SESSION=labwc
export XCURSOR_THEME=@XCURSOR_THEME@
export XCURSOR_SIZE=@XCURSOR_SIZE@
export LABWC_UPDATE_ACTIVATION_ENV=1

if [[ -r "@RUNTIME_ENV_PATH@" ]]; then
  # shellcheck disable=SC1090,SC1091
  source "@RUNTIME_ENV_PATH@"
fi

exec labwc
