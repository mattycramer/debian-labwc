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

update_activation_environment() {
  [[ "${LABWC_UPDATE_ACTIVATION_ENV:-0}" == "1" ]] || return 0
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user import-environment "$@" >/dev/null 2>&1 || true
  fi
  if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --systemd "$@" >/dev/null 2>&1 || true
  fi
}

if command -v gpgconf >/dev/null 2>&1; then
  gpgconf --launch gpg-agent >/dev/null 2>&1 || true
  current_tty="$(tty 2>/dev/null || true)"
  if [[ -n "${current_tty:-}" && "${current_tty}" != "not a tty" ]]; then
    export GPG_TTY="$current_tty"
    update_activation_environment GPG_TTY
  fi
  gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1 || true
  ssh_agent_socket="$(gpgconf --list-dirs agent-ssh-socket 2>/dev/null || true)"
  if [[ -n "${ssh_agent_socket:-}" ]]; then
    export SSH_AUTH_SOCK="$ssh_agent_socket"
    update_activation_environment SSH_AUTH_SOCK
  fi
fi

update_activation_environment \
  XDG_CURRENT_DESKTOP \
  XDG_SESSION_TYPE \
  XDG_SESSION_DESKTOP \
  DESKTOP_SESSION \
  XCURSOR_THEME \
  XCURSOR_SIZE \
  PASSWORD_STORE \
  ELECTRON_OZONE_PLATFORM_HINT \
  QT_QPA_PLATFORM \
  QT_WAYLAND_DISABLE_WINDOWDECORATION

exec labwc
