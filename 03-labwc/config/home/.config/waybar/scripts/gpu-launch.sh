#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly WOFI_PROMPT='Launch on Nvidia GPU'

show_error() {
  local message="$1"
  if command -v wofi >/dev/null 2>&1; then
    printf '%s\n' "$message" |
      wofi \
        --dmenu \
        --prompt 'Nvidia GPU' \
        --lines 1 \
        --hide-scroll \
        --cache-file /dev/null \
        --insensitive >/dev/null 2>&1 || true
  else
    printf '%s\n' "$message" >&2
  fi
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    show_error "Missing required command: ${command_name}"
    exit 1
  fi
}

trim_leading_whitespace() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  printf '%s\n' "$value"
}

find_nvidia_gpu_id() {
  local gpu_id=""
  local gpu_name=""
  local is_discrete="no"
  local line

  while IFS= read -r line; do
    case "$line" in
      Device:\ *)
        gpu_id="${line#Device: }"
        gpu_name=""
        is_discrete="no"
        ;;
      "  Name:"*)
        gpu_name="$(trim_leading_whitespace "${line#  Name:}")"
        ;;
      "  Discrete:"*)
        is_discrete="$(trim_leading_whitespace "${line#  Discrete:}")"
        is_discrete="${is_discrete,,}"
        if [[ "$is_discrete" == "yes" && "${gpu_name,,}" == *nvidia* ]]; then
          printf '%s\n' "$gpu_id"
          return 0
        fi
        ;;
    esac
  done < <(switcherooctl list 2>/dev/null)

  return 1
}

select_desktop_file() {
  wofi \
    --show drun \
    --prompt "$WOFI_PROMPT" \
    --allow-images \
    --insensitive \
    --gtk-dark \
    --cache-file /dev/null \
    --no-actions \
    --define=drun-print_desktop_file=true \
    --define=drun-disable_prime=true
}

launch_desktop_file() {
  local desktop_file="$1"
  local gpu_id="$2"
  local error_message=""

  if [[ ! -f "$desktop_file" ]]; then
    show_error "Selected desktop entry is no longer available"
    exit 1
  fi

  if ! error_message="$(
    python3 - "$desktop_file" "$gpu_id" <<'PY'
import configparser
import os
import shlex
import shutil
import subprocess
import sys


def fail(message: str) -> "None":
    raise SystemExit(message)


def expand_exec_tokens(tokens, *, desktop_file: str, app_name: str, app_icon: str):
    expanded = []
    deprecated_codes = {"f", "F", "u", "U", "d", "D", "n", "N", "v", "m"}

    for token in tokens:
        if token == "%i":
            if app_icon:
                expanded.extend(["--icon", app_icon])
            continue

        pieces = []
        index = 0
        while index < len(token):
            character = token[index]
            if character != "%":
                pieces.append(character)
                index += 1
                continue

            index += 1
            if index >= len(token):
                pieces.append("%")
                break

            code = token[index]
            index += 1

            if code == "%":
                pieces.append("%")
            elif code == "c":
                pieces.append(app_name)
            elif code == "k":
                pieces.append(desktop_file)
            elif code == "i":
                if app_icon:
                    pieces.append(app_icon)
            elif code in deprecated_codes:
                continue
            else:
                fail(f"Desktop entry Exec contains an unsupported field code: %{code}")

        expanded_token = "".join(pieces)
        if expanded_token:
            expanded.append(expanded_token)

    return expanded


def terminal_prefix(app_name: str):
    footclient = shutil.which("footclient")
    if footclient:
        return [footclient, "-T", app_name, "-e"]

    foot = shutil.which("foot")
    if foot:
        return [foot, "-T", app_name, "-e"]

    fail("No supported terminal launcher is available for a Terminal=true desktop entry")


desktop_file = sys.argv[1]
gpu_id = sys.argv[2]

parser = configparser.RawConfigParser(interpolation=None, strict=False)
parser.optionxform = str

try:
    with open(desktop_file, encoding="utf-8") as handle:
        parser.read_file(handle)
except OSError as exc:
    fail(f"Unable to read desktop entry: {exc}")

if not parser.has_section("Desktop Entry"):
    fail("Desktop entry is missing the [Desktop Entry] section")

entry = parser["Desktop Entry"]

entry_type = entry.get("Type", "Application").strip()
if entry_type and entry_type != "Application":
    fail(f"Unsupported desktop entry type: {entry_type}")

exec_line = entry.get("Exec", "").strip()
if not exec_line:
    fail("Desktop entry is missing an Exec command")

app_name = entry.get("Name", "").strip() or "Application"
app_icon = entry.get("Icon", "").strip()
working_directory = entry.get("Path", "").strip() or None
if working_directory and not os.path.isdir(working_directory):
    working_directory = None

try:
    tokens = shlex.split(exec_line, posix=True)
except ValueError as exc:
    fail(f"Unable to parse Exec command: {exc}")

command = expand_exec_tokens(
    tokens,
    desktop_file=desktop_file,
    app_name=app_name,
    app_icon=app_icon,
)

if not command:
    fail("Desktop entry Exec command resolved to an empty launch command")

if "/" not in command[0] and shutil.which(command[0]) is None:
    fail(f"Desktop entry executable is not available: {command[0]}")

if entry.get("Terminal", "false").strip().lower() == "true":
    command = terminal_prefix(app_name) + command

launch_command = ["switcherooctl", "launch", f"--gpu={gpu_id}", *command]

try:
    subprocess.Popen(
        launch_command,
        cwd=working_directory,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
except OSError as exc:
    fail(f"Unable to start application with switcherooctl: {exc}")
PY
  )"; then
    show_error "${error_message:-Unable to launch desktop entry on the Nvidia GPU}"
    exit 1
  fi
}

main() {
  local gpu_id=""
  local selected_desktop_file=""

  require_command switcherooctl
  require_command wofi
  require_command python3

  gpu_id="$(find_nvidia_gpu_id)" || {
    show_error "No discrete Nvidia GPU was detected"
    exit 1
  }

  selected_desktop_file="$(select_desktop_file)" || exit 0
  [[ -n "$selected_desktop_file" ]] || exit 0

  launch_desktop_file "$selected_desktop_file" "$gpu_id"
}

main "$@"
