#!/usr/bin/env bash

readonly TASKBAR_DAEMON_SOURCE="$SCRIPT_DIR/src/debian-labwc-grouped-taskbar-daemon.c"
readonly TASKBAR_DAEMON_BUILD_DIR=".cache/debian-labwc/build/grouped-taskbar-daemon"
readonly TASKBAR_DAEMON_BUILD_PATH="debian-labwc-grouped-taskbar-daemon"
readonly TASKBAR_DAEMON_INSTALL_PATH="/usr/local/bin/debian-labwc-grouped-taskbar-daemon"
readonly WAYLAND_CLIENT_SO="/usr/lib/x86_64-linux-gnu/libwayland-client.so.0"

install_grouped_taskbar_daemon() {
  [[ -f "$TASKBAR_DAEMON_SOURCE" ]] || die "missing grouped taskbar daemon source: $TASKBAR_DAEMON_SOURCE"
  [[ -f "$WAYLAND_CLIENT_SO" ]] || die "missing Wayland client runtime library: $WAYLAND_CLIENT_SO"

  local build_root="$LABWC_TARGET_HOME/$TASKBAR_DAEMON_BUILD_DIR"
  local build_binary="$build_root/$TASKBAR_DAEMON_BUILD_PATH"

  run_cmd install -d -m 0755 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" "$build_root"
  run_cmd runuser -u "$LABWC_TARGET_USER" -- env HOME="$LABWC_TARGET_HOME" \
    gcc \
      -std=c11 \
      -O2 \
      -Wall \
      -Wextra \
      -Werror \
      -D_POSIX_C_SOURCE=200809L \
      "$TASKBAR_DAEMON_SOURCE" \
      "$WAYLAND_CLIENT_SO" \
      -o "$build_binary"
  run_cmd install -m 0755 "$build_binary" "$TASKBAR_DAEMON_INSTALL_PATH"
}
