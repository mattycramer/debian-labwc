#!/usr/bin/env bash

readonly THINKPAD_UDEV_HWDB_DIR="/etc/udev/hwdb.d"
readonly THINKPAD_UDEV_HWDB_PATH="/etc/udev/hwdb.d/90-labwc-thinkpad-extra-buttons.hwdb"

render_thinkpad_hwdb_override() {
  local content
  content="$(cat <<'EOF'
# Managed by labwc.
# The stock systemd keyboard hwdb maps several newer ThinkPad extra-button
# scan codes to Teams/notification actions. On some ThinkPad firmware/input
# stacks these remaps fail with EVIOCSKEYCODE Invalid argument during udev
# initialization. Neutralize the problematic remaps locally.
evdev:name:ThinkPad Extra Buttons:dmi:bvn*:bvr*:bd*:svnLENOVO*:pn*:*
 KEYBOARD_KEY_4b=reserved
 KEYBOARD_KEY_4c=reserved
 KEYBOARD_KEY_4d=reserved
EOF
)"
  run_cmd install -d -m 0755 "$THINKPAD_UDEV_HWDB_DIR"
  write_text_file "$THINKPAD_UDEV_HWDB_PATH" "$content"
}

apply_thinkpad_hwdb_override() {
  render_thinkpad_hwdb_override
  run_cmd systemd-hwdb update
  run_cmd udevadm trigger --subsystem-match=input --action=change
}

verify_thinkpad_hwdb_override() {
  verify_path_exists "$THINKPAD_UDEV_HWDB_PATH"
  grep -F 'KEYBOARD_KEY_4b=reserved' "$THINKPAD_UDEV_HWDB_PATH" >/dev/null || die "ThinkPad hwdb override missing KEYBOARD_KEY_4b neutralization"
  grep -F 'KEYBOARD_KEY_4c=reserved' "$THINKPAD_UDEV_HWDB_PATH" >/dev/null || die "ThinkPad hwdb override missing KEYBOARD_KEY_4c neutralization"
  grep -F 'KEYBOARD_KEY_4d=reserved' "$THINKPAD_UDEV_HWDB_PATH" >/dev/null || die "ThinkPad hwdb override missing KEYBOARD_KEY_4d neutralization"
}

remove_thinkpad_hwdb_override() {
  run_cmd rm -f -- "$THINKPAD_UDEV_HWDB_PATH"
  run_cmd systemd-hwdb update
  run_cmd udevadm trigger --subsystem-match=input --action=change
}
