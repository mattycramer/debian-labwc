#!/usr/bin/env bash

runtime_env_path() {
  printf '%s/.config/debian-labwc/runtime.env\n' "$LABWC_TARGET_HOME"
}

session_wrapper_path() {
  printf '%s\n' "/usr/local/bin/debian-labwc-session"
}
