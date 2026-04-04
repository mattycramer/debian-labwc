#!/usr/bin/env bash
set -u
set -o pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
TIMESTAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
BUNDLE_ROOT="${SCRIPT_DIR}/artifacts/${TIMESTAMP}"

readonly SCRIPT_DIR
readonly REPO_ROOT
readonly TIMESTAMP
readonly BUNDLE_ROOT

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

log_info() {
  printf '[%s] INFO: %s\n' "$(timestamp)" "$*"
}

log_warn() {
  printf '[%s] WARN: %s\n' "$(timestamp)" "$*" >&2
}

write_note() {
  local destination="$1"
  shift
  mkdir -p -- "$(dirname -- "$destination")"
  printf '%s\n' "$*" >"$destination"
}

ensure_dir() {
  mkdir -p -- "$1"
}

greeter_uid() {
  local uid_value=""

  uid_value="$(getent passwd greeter 2>/dev/null | awk -F: '{print $3}')"
  if [ -n "$uid_value" ]; then
    printf '%s\n' "$uid_value"
    return 0
  fi
  printf '%s\n' "999"
}

greetd_vt() {
  local vt_value=""

  if [ -r /etc/greetd/config.toml ]; then
    vt_value="$(awk -F= '
      /^\[terminal\]/ {in_terminal=1; next}
      /^\[/ && $0 != "[terminal]" {in_terminal=0}
      in_terminal && $1 ~ /^[[:space:]]*vt[[:space:]]*$/ {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
        gsub(/"/, "", $2)
        print $2
        exit
      }
    ' /etc/greetd/config.toml)"
  fi

  case "$vt_value" in
    ''|*[!0-9]*)
      printf '%s\n' "7"
      ;;
    *)
      printf '%s\n' "$vt_value"
      ;;
  esac
}

run_and_capture() {
  local relative_path="$1"
  shift
  local destination="${BUNDLE_ROOT}/${relative_path}"
  local status=0

  mkdir -p -- "$(dirname -- "$destination")"
  {
    printf 'timestamp=%s\n' "$(timestamp)"
    printf 'cwd=%s\n' "$REPO_ROOT"
    printf 'command='
    printf '%q ' "$@"
    printf '\n\n'
    "$@"
  } >"$destination" 2>&1 || status=$?

  if [ "$status" -ne 0 ]; then
    printf '\nexit_status=%s\n' "$status" >>"$destination"
  fi

  return 0
}

copy_text_file() {
  local source_path="$1"
  local relative_path="$2"
  local destination="${BUNDLE_ROOT}/${relative_path}"

  mkdir -p -- "$(dirname -- "$destination")"
  if [ ! -e "$source_path" ]; then
    write_note "$destination" "missing: ${source_path}"
    return 0
  fi
  if [ ! -r "$source_path" ]; then
    write_note "$destination" "not readable: ${source_path}"
    return 0
  fi
  if [ ! -s "$source_path" ]; then
    write_note "$destination" "empty: ${source_path}"
    return 0
  fi
  cp -a -- "$source_path" "$destination"
}

copy_path_tree() {
  local source_path="$1"
  local relative_path="$2"
  local destination="${BUNDLE_ROOT}/${relative_path}"

  mkdir -p -- "$(dirname -- "$destination")"
  if [ ! -e "$source_path" ]; then
    write_note "${destination}.txt" "missing: ${source_path}"
    return 0
  fi
  if [ ! -r "$source_path" ]; then
    write_note "${destination}.txt" "not readable: ${source_path}"
    return 0
  fi
  cp -a -- "$source_path" "$destination" 2>"${destination}.stderr" || {
    write_note "${destination}.txt" "copy failed: ${source_path}"
    return 0
  }
  if [ -f "${destination}.stderr" ] && [ ! -s "${destination}.stderr" ]; then
    rm -f -- "${destination}.stderr"
  fi
}

find_repo_file() {
  local relative_path="$1"
  printf '%s\n' "${REPO_ROOT}/${relative_path}"
}

apt_runner() {
  if [ "$(id -u)" -eq 0 ]; then
    printf '%s\n' ""
    return 0
  fi
  if command -v sudo >/dev/null 2>&1; then
    printf '%s\n' "sudo"
    return 0
  fi
  return 1
}

ensure_debug_packages() {
  local runner=""
  local missing=()
  local package_name
  local command_name
  local mapping

  while IFS='|' read -r command_name package_name; do
    [ -n "$command_name" ] || continue
    if ! command -v "$command_name" >/dev/null 2>&1; then
      missing+=("$package_name")
    fi
  done <<'EOF'
lspci|pciutils
lsusb|usbutils
gdb|gdb
vulkaninfo|vulkan-tools
vainfo|vainfo
EOF

  if [ "${#missing[@]}" -eq 0 ]; then
    run_and_capture "meta/package-bootstrap.txt" printf '%s\n' "no additional debug packages were needed"
    return 0
  fi

  if ! runner="$(apt_runner)"; then
    write_note "${BUNDLE_ROOT}/meta/package-bootstrap.txt" \
      "missing helper packages: ${missing[*]}" \
      "skipped install because neither root nor sudo is available"
    return 0
  fi

  if [ -n "$runner" ]; then
    run_and_capture "meta/apt-update.txt" timeout 600 "$runner" env DEBIAN_FRONTEND=noninteractive apt-get update
    run_and_capture "meta/apt-install.txt" timeout 1200 "$runner" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"
  else
    run_and_capture "meta/apt-update.txt" timeout 600 env DEBIAN_FRONTEND=noninteractive apt-get update
    run_and_capture "meta/apt-install.txt" timeout 1200 env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"
  fi
}

collect_repo_context() {
  run_and_capture "meta/date.txt" date -u
  run_and_capture "meta/uname.txt" uname -a
  run_and_capture "meta/id.txt" id
  run_and_capture "meta/df.txt" df -h
  run_and_capture "meta/free.txt" free -h
  run_and_capture "meta/ps.txt" ps -ef
  run_and_capture "repo/pwd.txt" pwd
  run_and_capture "repo/git-status.txt" git -C "$REPO_ROOT" -c color.ui=never status -sb
  run_and_capture "repo/git-branch.txt" git -C "$REPO_ROOT" -c color.ui=never branch --show-current
  run_and_capture "repo/git-rev.txt" git -C "$REPO_ROOT" rev-parse HEAD
  run_and_capture "repo/git-diff-stat.txt" git -C "$REPO_ROOT" -c color.ui=never diff --stat
  run_and_capture "repo/git-diff.txt" git -C "$REPO_ROOT" -c color.ui=never diff
  copy_text_file "$(find_repo_file "03-labwc/.env")" "repo/03-labwc.env"
}

collect_systemd_and_logs() {
  local vt_value
  vt_value="$(greetd_vt)"

  run_and_capture "systemd/systemctl-failed.txt" systemctl --failed --no-pager
  run_and_capture "systemd/greetd-status.txt" systemctl status greetd.service --no-pager
  run_and_capture "systemd/greetd-show.txt" systemctl show greetd.service
  run_and_capture "systemd/greetd-cat.txt" systemctl cat greetd.service
  run_and_capture "systemd/getty-tty${vt_value}-status.txt" systemctl status "getty@tty${vt_value}.service" --no-pager
  run_and_capture "systemd/getty-tty${vt_value}-cat.txt" systemctl cat "getty@tty${vt_value}.service"
  run_and_capture "systemd/journal-greetd-boot.txt" journalctl -b -u greetd.service --no-pager
  run_and_capture "systemd/journal-greetd-tail.txt" journalctl -u greetd.service -n 300 --no-pager
  run_and_capture "systemd/journal-err-boot.txt" journalctl -p err..alert -b --no-pager
  copy_text_file "/var/log/regreet/log" "logs/regreet.log"
  copy_text_file "/var/log/regreet/greeter-session.log" "logs/regreet-greeter-session.log"
  copy_path_tree "/var/lib/regreet" "runtime/var-lib-regreet"
}

collect_greetd_labwc_config() {
  copy_path_tree "/etc/greetd" "configs/etc-greetd"
  copy_path_tree "/etc/labwc-greeter" "configs/etc-labwc-greeter"
  copy_text_file "/etc/systemd/system/greetd.service.d/20-labwc-vt.conf" "configs/greetd-vt-dropin.conf"
  copy_text_file "/usr/local/bin/labwc-greeter-session" "configs/usr-local-bin-labwc-greeter-session"
  copy_text_file "/usr/local/bin/labwc-greeter-regreet" "configs/usr-local-bin-labwc-greeter-regreet"
  copy_text_file "/usr/local/bin/regreet" "configs/usr-local-bin-regreet"
  copy_text_file "/usr/share/wayland-sessions/labwc.desktop" "configs/usr-share-wayland-sessions-labwc.desktop"
}

collect_runtime_state() {
  local uid_value
  uid_value="$(greeter_uid)"

  run_and_capture "runtime/loginctl-list-sessions.txt" loginctl list-sessions
  run_and_capture "runtime/loginctl-list-users.txt" loginctl list-users
  run_and_capture "runtime/loginctl-seat0.txt" loginctl seat-status seat0
  run_and_capture "runtime/loginctl-user-greeter.txt" loginctl user-status greeter
  run_and_capture "runtime/loginctl-greeter-sessions.txt" loginctl show-user greeter
  run_and_capture "systemd/journal-user-${uid_value}.txt" journalctl "_UID=${uid_value}" -b --no-pager
  run_and_capture "runtime/greeter-passwd.txt" getent passwd greeter
  run_and_capture "runtime/greeter-groups.txt" id greeter
  run_and_capture "runtime/run-user-${uid_value}.txt" ls -la "/run/user/${uid_value}"
  run_and_capture "runtime/run-user-${uid_value}-find.txt" find "/run/user/${uid_value}" -maxdepth 2 -mindepth 1 -printf '%y %m %u %g %p\n'
  run_and_capture "runtime/greetd-sockets.txt" find /run -maxdepth 2 \( -name 'greetd*.sock' -o -name 'greetd-*' \) -printf '%y %m %u %g %p\n'
  run_and_capture "runtime/dri-devices.txt" find /dev/dri -maxdepth 2 -printf '%y %m %u %g %p\n'
}

collect_graphics_state() {
  run_and_capture "hardware/lspci-nnk.txt" lspci -nnk
  run_and_capture "hardware/lsusb.txt" lsusb
  run_and_capture "hardware/lsmod.txt" lsmod
  run_and_capture "hardware/modinfo-i915.txt" modinfo i915
  run_and_capture "hardware/modinfo-amdgpu.txt" modinfo amdgpu
  run_and_capture "hardware/modinfo-nvidia.txt" modinfo nvidia
  run_and_capture "hardware/drm-tree.txt" find /sys/class/drm -maxdepth 3 -printf '%y %p\n'
  run_and_capture "hardware/drm-status.txt" sh -c 'for node in /sys/class/drm/*/status; do [ -e "$node" ] || continue; printf "%s: " "$node"; cat "$node"; done'
  run_and_capture "hardware/dmesg-drm.txt" dmesg
  run_and_capture "hardware/vulkaninfo-summary.txt" vulkaninfo --summary
  run_and_capture "hardware/vainfo.txt" vainfo
}

collect_binary_diagnostics() {
  run_and_capture "binaries/regreet-file.txt" file /usr/local/bin/regreet
  run_and_capture "binaries/regreet-ldd.txt" ldd /usr/local/bin/regreet
  run_and_capture "binaries/regreet-version.txt" /usr/local/bin/regreet --version
  run_and_capture "binaries/labwc-version.txt" /usr/bin/labwc --version
  run_and_capture "binaries/gtk-query-settings.txt" sh -c 'command -v gtk4-query-settings >/dev/null 2>&1 && gtk4-query-settings || printf "%s\n" "gtk4-query-settings unavailable"'
  run_and_capture "packages/dpkg-relevant.txt" sh -c '
    dpkg-query -W -f='"'"'${binary:Package}\t${Version}\n'"'"' \
      greetd labwc dbus dbus-broker libgtk-4-1 libadwaita-1-0 mesa-vulkan-drivers libegl1 libgl1-mesa-dri \
      vulkan-tools vainfo pciutils gdb 2>/dev/null
  '
  run_and_capture "packages/apt-policy-relevant.txt" apt-cache policy \
    greetd labwc dbus dbus-broker libgtk-4-1 libadwaita-1-0 mesa-vulkan-drivers libegl1 libgl1-mesa-dri
}

collect_coredump_state() {
  run_and_capture "coredump/coredump-list-regreet.txt" coredumpctl list /usr/local/bin/regreet
  run_and_capture "coredump/coredump-info-regreet.txt" coredumpctl info /usr/local/bin/regreet
  run_and_capture "coredump/coredump-info-greetd.txt" coredumpctl info greetd
  run_and_capture "coredump/coredump-gdb-regreet.txt" \
    coredumpctl debug /usr/local/bin/regreet --debugger=gdb --debugger-arguments='-batch -ex "set pagination off" -ex "thread apply all bt full" -ex "quit"'
}

write_manifest() {
  run_and_capture "meta/find-bundle.txt" sh -c 'find "$1" -type f | LC_ALL=C sort' sh "$BUNDLE_ROOT"
}

main() {
  ensure_dir "$BUNDLE_ROOT"
  log_info "writing debug bundle to ${BUNDLE_ROOT}"

  ensure_debug_packages
  collect_repo_context
  collect_systemd_and_logs
  collect_greetd_labwc_config
  collect_runtime_state
  collect_graphics_state
  collect_binary_diagnostics
  collect_coredump_state
  write_manifest

  log_info "debug bundle ready at ${BUNDLE_ROOT}"
}

main "$@"
