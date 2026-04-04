#!/usr/bin/env bash
set -u
set -o pipefail
IFS=$'\n\t'
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

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

log_phase() {
  printf '\n[%s] PHASE: %s\n' "$(timestamp)" "$*"
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

command_exists() {
  command -v "$1" >/dev/null 2>&1
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
  run_and_capture_allowed "$relative_path" "0" "$@"
}

run_and_capture_allowed() {
  local relative_path="$1"
  local allowed_statuses="$2"
  shift 2
  local destination="${BUNDLE_ROOT}/${relative_path}"
  local status=0
  local allowed=0

  mkdir -p -- "$(dirname -- "$destination")"
  {
    printf 'timestamp=%s\n' "$(timestamp)"
    printf 'cwd=%s\n' "$REPO_ROOT"
    printf 'command='
    printf '%q ' "$@"
    printf '\n\n'
    "$@"
  } >"$destination" 2>&1 || status=$?

  if [[ " ${allowed_statuses} " == *" ${status} "* ]]; then
    allowed=1
  fi

  if [ "$allowed" -eq 0 ]; then
    printf '\nexit_status=%s\n' "$status" >>"$destination"
    log_warn "${relative_path} exited with status ${status}"
  fi

  return 0
}

run_optional_command() {
  local relative_path="$1"
  local command_name="$2"
  shift 2

  if ! command_exists "$command_name"; then
    write_note "${BUNDLE_ROOT}/${relative_path}" "missing command: ${command_name}"
    return 0
  fi

  run_and_capture "$relative_path" "$@"
}

run_optional_command_allowed() {
  local relative_path="$1"
  local allowed_statuses="$2"
  local command_name="$3"
  shift 3

  if ! command_exists "$command_name"; then
    write_note "${BUNDLE_ROOT}/${relative_path}" "missing command: ${command_name}"
    return 0
  fi

  run_and_capture_allowed "$relative_path" "$allowed_statuses" "$@"
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
  local command_name
  local package_name
  local suite_name
  local entry
  local install_status=0

  while IFS='|' read -r command_name package_name suite_name; do
    [ -n "$command_name" ] || continue
    if ! command_exists "$command_name"; then
      missing+=("${command_name}|${package_name}|${suite_name}")
    fi
  done <<'EOF'
lspci|pciutils|sid
lsusb|usbutils|sid
gdb|gdb|sid
vulkaninfo|vulkan-tools|sid
vainfo|vainfo|sid
coredumpctl|systemd-coredump|sid
file|file|sid
strings|binutils|sid
modinfo|kmod|sid
lsmod|kmod|sid
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
  else
    run_and_capture "meta/apt-update.txt" timeout 600 env DEBIAN_FRONTEND=noninteractive apt-get update
  fi

  for entry in "${missing[@]}"; do
    IFS='|' read -r command_name package_name suite_name <<EOF
$entry
EOF
    if [ -n "$runner" ]; then
      run_and_capture "meta/packages/${command_name}.txt" timeout 1200 "$runner" env DEBIAN_FRONTEND=noninteractive apt-get -t "$suite_name" install -y --no-install-recommends "$package_name"
    else
      run_and_capture "meta/packages/${command_name}.txt" timeout 1200 env DEBIAN_FRONTEND=noninteractive apt-get -t "$suite_name" install -y --no-install-recommends "$package_name"
    fi
    if ! command_exists "$command_name"; then
      install_status=1
    fi
  done

  if [ "$install_status" -ne 0 ]; then
    write_note "${BUNDLE_ROOT}/meta/package-bootstrap.txt" \
      "one or more helper commands are still unavailable after bootstrap" \
      "see meta/packages/*.txt for per-command install attempts"
    return 0
  fi

  write_note "${BUNDLE_ROOT}/meta/package-bootstrap.txt" \
    "helper package bootstrap completed" \
    "see meta/packages/*.txt for per-command install logs"
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
  run_and_capture_allowed "systemd/greetd-status.txt" "0 3" systemctl status greetd.service --no-pager
  run_and_capture "systemd/greetd-show.txt" systemctl show greetd.service
  run_and_capture "systemd/greetd-cat.txt" systemctl cat greetd.service
  run_and_capture_allowed "systemd/getty-tty${vt_value}-status.txt" "0 3 4" systemctl status "getty@tty${vt_value}.service" --no-pager
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
  run_and_capture_allowed "runtime/loginctl-user-greeter.txt" "0 1" loginctl user-status greeter
  run_and_capture_allowed "runtime/loginctl-greeter-sessions.txt" "0 1" loginctl show-user greeter
  run_and_capture "systemd/journal-user-${uid_value}.txt" journalctl "_UID=${uid_value}" -b --no-pager
  run_and_capture "runtime/greeter-passwd.txt" getent passwd greeter
  run_and_capture "runtime/greeter-groups.txt" id greeter
  run_and_capture_allowed "runtime/run-user-${uid_value}.txt" "0 1 2" ls -la "/run/user/${uid_value}"
  run_and_capture_allowed "runtime/run-user-${uid_value}-find.txt" "0 1" find "/run/user/${uid_value}" -maxdepth 2 -mindepth 1 -printf '%y %m %u %g %p\n'
  run_and_capture "runtime/greetd-sockets.txt" find /run -maxdepth 2 \( -name 'greetd*.sock' -o -name 'greetd-*' \) -printf '%y %m %u %g %p\n'
  run_and_capture "runtime/dri-devices.txt" find /dev/dri -maxdepth 2 -printf '%y %m %u %g %p\n'
}

collect_graphics_state() {
  run_optional_command "hardware/lspci-nnk.txt" lspci lspci -nnk
  run_optional_command "hardware/lsusb.txt" lsusb lsusb
  run_optional_command "hardware/lsmod.txt" lsmod lsmod
  run_optional_command_allowed "hardware/modinfo-i915.txt" "0 1" modinfo modinfo i915
  run_optional_command_allowed "hardware/modinfo-amdgpu.txt" "0 1" modinfo modinfo amdgpu
  run_optional_command_allowed "hardware/modinfo-nvidia.txt" "0 1" modinfo modinfo nvidia
  run_and_capture "hardware/drm-tree.txt" find /sys/class/drm -maxdepth 3 -printf '%y %p\n'
  run_and_capture "hardware/drm-status.txt" sh -c 'for node in /sys/class/drm/*/status; do [ -e "$node" ] || continue; printf "%s: " "$node"; cat "$node"; done'
  run_and_capture_allowed "hardware/dmesg-drm.txt" "0 1" dmesg
  run_optional_command_allowed "hardware/vulkaninfo-summary.txt" "0 1" vulkaninfo vulkaninfo --summary
  run_optional_command_allowed "hardware/vainfo.txt" "0 1" vainfo vainfo
}

collect_binary_diagnostics() {
  run_optional_command "binaries/regreet-file.txt" file file /usr/local/bin/regreet
  run_and_capture "binaries/regreet-ldd.txt" ldd /usr/local/bin/regreet
  run_and_capture_allowed "binaries/regreet-version.txt" "0 1" /usr/local/bin/regreet --version
  run_and_capture_allowed "binaries/labwc-version.txt" "0 1" /usr/bin/labwc --version
  run_and_capture "binaries/gtk-query-settings.txt" sh -c 'command -v gtk4-query-settings >/dev/null 2>&1 && gtk4-query-settings || printf "%s\n" "gtk4-query-settings unavailable"'
  run_and_capture_allowed "packages/dpkg-relevant.txt" "0 1" sh -c '
    dpkg-query -W -f='"'"'${binary:Package}\t${Version}\n'"'"' \
      greetd labwc dbus dbus-broker libgtk-4-1 libadwaita-1-0 mesa-vulkan-drivers libegl1 libgl1-mesa-dri \
      vulkan-tools vainfo pciutils gdb 2>/dev/null
  '
  run_and_capture "packages/apt-policy-relevant.txt" apt-cache policy \
    greetd labwc dbus dbus-broker libgtk-4-1 libadwaita-1-0 mesa-vulkan-drivers libegl1 libgl1-mesa-dri
}

collect_coredump_state() {
  run_optional_command_allowed "coredump/coredump-list-regreet.txt" "0 1" coredumpctl coredumpctl list /usr/local/bin/regreet
  run_optional_command_allowed "coredump/coredump-info-regreet.txt" "0 1" coredumpctl coredumpctl info /usr/local/bin/regreet
  run_optional_command_allowed "coredump/coredump-info-greetd.txt" "0 1" coredumpctl coredumpctl info greetd
  if command_exists coredumpctl && command_exists gdb; then
    run_and_capture_allowed "coredump/coredump-gdb-regreet.txt" "0 1" \
      coredumpctl debug /usr/local/bin/regreet --debugger=gdb --debugger-arguments='-batch -ex "set pagination off" -ex "thread apply all bt full" -ex "quit"'
  else
    write_note "${BUNDLE_ROOT}/coredump/coredump-gdb-regreet.txt" "missing command: coredumpctl or gdb"
  fi
}

write_manifest() {
  run_and_capture "meta/find-bundle.txt" sh -c 'find "$1" -type f | LC_ALL=C sort' sh "$BUNDLE_ROOT"
}

main() {
  ensure_dir "$BUNDLE_ROOT"
  log_info "writing debug bundle to ${BUNDLE_ROOT}"

  log_phase "bootstrap debug tools"
  ensure_debug_packages
  log_phase "collect repo context"
  collect_repo_context
  log_phase "collect systemd and logs"
  collect_systemd_and_logs
  log_phase "collect greetd and labwc config"
  collect_greetd_labwc_config
  log_phase "collect runtime state"
  collect_runtime_state
  log_phase "collect graphics state"
  collect_graphics_state
  log_phase "collect binary and package diagnostics"
  collect_binary_diagnostics
  log_phase "collect coredump state"
  collect_coredump_state
  log_phase "write bundle manifest"
  write_manifest

  log_info "debug bundle ready at ${BUNDLE_ROOT}"
}

main "$@"
