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
export PASSWORD_STORE=kwallet6
export ELECTRON_OZONE_PLATFORM_HINT=wayland
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

if command -v gpgconf >/dev/null 2>&1; then
  gpgconf --launch gpg-agent >/dev/null 2>&1 || true
  current_tty="$(tty 2>/dev/null || true)"
  if [[ -n "${current_tty:-}" && "${current_tty}" != "not a tty" ]]; then
    export GPG_TTY="$current_tty"
    systemctl --user import-environment GPG_TTY >/dev/null 2>&1 || true
  fi
  gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1 || true
  ssh_agent_socket="$(gpgconf --list-dirs agent-ssh-socket 2>/dev/null || true)"
  if [[ -n "${ssh_agent_socket:-}" ]]; then
    export SSH_AUTH_SOCK="$ssh_agent_socket"
    systemctl --user import-environment SSH_AUTH_SOCK >/dev/null 2>&1 || true
  fi
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user import-environment \
    PASSWORD_STORE \
    ELECTRON_OZONE_PLATFORM_HINT \
    QT_QPA_PLATFORM \
    QT_WAYLAND_DISABLE_WINDOWDECORATION >/dev/null 2>&1 || true
fi

exec labwc
