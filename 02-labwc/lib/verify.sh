#!/usr/bin/env bash

verify_path_mode() {
  local path="$1"
  local expected="$2"

  stat -c '%U:%G:%a' "$path" | grep -Fx "$expected" >/dev/null || {
    die "${path} has unexpected ownership or mode (expected ${expected})"
  }
}

verify_regreet_install() {
  require_file "$(regreet_binary_path)"
  require_file "$(regreet_provenance_path)"
  [[ -x "$(regreet_binary_path)" ]] || die "regreet binary is not executable"
  case "${LABWC_INSTALL_METHOD:-}" in
    source)
      grep -F 'REGREET_INSTALL_METHOD="source"' "$(regreet_provenance_path)" >/dev/null || {
        die "regreet provenance does not record the source install method"
      }
      grep -F "REGREET_COMMIT_SHA=\"$REGREET_COMMIT_SHA\"" "$(regreet_provenance_path)" >/dev/null || {
        die "regreet provenance does not record expected commit"
      }
      grep -F "REGREET_RUST_TOOLCHAIN=\"$REGREET_RUST_TOOLCHAIN\"" "$(regreet_provenance_path)" >/dev/null || {
        die "regreet provenance does not record expected rust toolchain"
      }
      ;;
    artifact)
      grep -F 'REGREET_INSTALL_METHOD="artifact"' "$(regreet_provenance_path)" >/dev/null || {
        die "regreet provenance does not record the artifact install method"
      }
      grep -F "REGREET_TARBALL_URL=\"$REGREET_TARBALL_URL\"" "$(regreet_provenance_path)" >/dev/null || {
        die "regreet provenance does not record expected tarball URL"
      }
      grep -F "REGREET_TARBALL_SHA=\"$(normalize_sha256_value "$REGREET_TARBALL_SHA")\"" "$(regreet_provenance_path)" >/dev/null || {
        die "regreet provenance does not record expected tarball sha"
      }
      grep -F "REGREET_COMMIT_TAG=\"$REGREET_COMMIT_TAG\"" "$(regreet_provenance_path)" >/dev/null || {
        die "regreet provenance does not record expected commit tag"
      }
      grep -F "REGREET_COMMIT_SHA=\"$REGREET_COMMIT_SHA\"" "$(regreet_provenance_path)" >/dev/null || {
        die "regreet provenance does not record expected commit"
      }
      ;;
    *)
      die "LABWC_INSTALL_METHOD must be 'source' or 'artifact', found '${LABWC_INSTALL_METHOD:-}'"
      ;;
  esac
  assert_binary_dependencies "$(regreet_binary_path)" "regreet"
  "$(regreet_binary_path)" --version >/dev/null 2>&1 || die "regreet --version failed"
}

verify_labwc_tweaks_install() {
  require_file "$LABWC_TWEAKS_BIN_PATH"
  require_file "$LABWC_TWEAKS_DESKTOP_PATH"
  require_file "$LABWC_TWEAKS_APPDATA_PATH"
  require_file "$LABWC_TWEAKS_ICON_PATH"
  require_file "$LABWC_TWEAKS_POLICY_PATH"
  require_file "$LABWC_TWEAKS_LOGIN_HELPER_PATH"
  require_file "$LABWC_TWEAKS_PROVENANCE_PATH"
  case "${LABWC_INSTALL_METHOD:-}" in
    source)
      grep -F 'LABWC_TWEAKS_INSTALL_METHOD="source"' "$LABWC_TWEAKS_PROVENANCE_PATH" >/dev/null || {
        die "labwc-tweaks provenance does not record the source install method"
      }
      grep -F "LABWC_TWEAKS_COMMIT_SHA=\"$LABWC_TWEAKS_COMMIT_SHA\"" "$LABWC_TWEAKS_PROVENANCE_PATH" >/dev/null || {
        die "labwc-tweaks provenance does not record expected commit"
      }
      ;;
    artifact)
      grep -F 'LABWC_TWEAKS_INSTALL_METHOD="artifact"' "$LABWC_TWEAKS_PROVENANCE_PATH" >/dev/null || {
        die "labwc-tweaks provenance does not record the artifact install method"
      }
      grep -F "LABWC_TWEAKS_TARBALL_URL=\"$LABWC_TWEAKS_TARBALL_URL\"" "$LABWC_TWEAKS_PROVENANCE_PATH" >/dev/null || {
        die "labwc-tweaks provenance does not record expected tarball URL"
      }
      grep -F "LABWC_TWEAKS_TARBALL_SHA=\"$(normalize_sha256_value "$LABWC_TWEAKS_TARBALL_SHA")\"" "$LABWC_TWEAKS_PROVENANCE_PATH" >/dev/null || {
        die "labwc-tweaks provenance does not record expected tarball sha"
      }
      grep -F "LABWC_TWEAKS_COMMIT_TAG=\"$LABWC_TWEAKS_COMMIT_TAG\"" "$LABWC_TWEAKS_PROVENANCE_PATH" >/dev/null || {
        die "labwc-tweaks provenance does not record expected commit tag"
      }
      grep -F "LABWC_TWEAKS_COMMIT_SHA=\"$LABWC_TWEAKS_COMMIT_SHA\"" "$LABWC_TWEAKS_PROVENANCE_PATH" >/dev/null || {
        die "labwc-tweaks provenance does not record expected commit"
      }
      ;;
    *)
      die "LABWC_INSTALL_METHOD must be 'source' or 'artifact', found '${LABWC_INSTALL_METHOD:-}'"
      ;;
  esac
  assert_binary_dependencies "$LABWC_TWEAKS_BIN_PATH" "labwc-tweaks"
  bash -n "$LABWC_TWEAKS_LOGIN_HELPER_PATH"
  grep -F 'org.labwc.labwc-tweaks.login-screen' "$LABWC_TWEAKS_POLICY_PATH" >/dev/null || {
    die "labwc-tweaks polkit policy is missing the managed login-screen action"
  }
}

verify_keepsecret_install() {
  require_file "$KEEPSECRET_BIN_PATH"
  require_file "$KEEPSECRET_DESKTOP_PATH"
  require_file "$KEEPSECRET_APPDATA_PATH"
  require_file "$KEEPSECRET_ICON_PATH"
  require_file "$KEEPSECRET_LOGGING_CATEGORIES_PATH"
  require_file "$KEEPSECRET_PROVENANCE_PATH"
  case "${LABWC_INSTALL_METHOD:-}" in
    source)
      grep -F 'KEEPSECRET_INSTALL_METHOD="source"' "$KEEPSECRET_PROVENANCE_PATH" >/dev/null || {
        die "keepsecret provenance does not record the source install method"
      }
      grep -F "KEEPSECRET_COMMIT_SHA=\"$KEEPSECRET_COMMIT_SHA\"" "$KEEPSECRET_PROVENANCE_PATH" >/dev/null || {
        die "keepsecret provenance does not record expected commit"
      }
      ;;
    artifact)
      grep -F 'KEEPSECRET_INSTALL_METHOD="artifact"' "$KEEPSECRET_PROVENANCE_PATH" >/dev/null || {
        die "keepsecret provenance does not record the artifact install method"
      }
      grep -F "KEEPSECRET_TARBALL_URL=\"$KEEPSECRET_TARBALL_URL\"" "$KEEPSECRET_PROVENANCE_PATH" >/dev/null || {
        die "keepsecret provenance does not record expected tarball URL"
      }
      grep -F "KEEPSECRET_TARBALL_SHA=\"$(normalize_sha256_value "$KEEPSECRET_TARBALL_SHA")\"" "$KEEPSECRET_PROVENANCE_PATH" >/dev/null || {
        die "keepsecret provenance does not record expected tarball sha"
      }
      grep -F "KEEPSECRET_COMMIT_TAG=\"$KEEPSECRET_COMMIT_TAG\"" "$KEEPSECRET_PROVENANCE_PATH" >/dev/null || {
        die "keepsecret provenance does not record expected commit tag"
      }
      grep -F "KEEPSECRET_COMMIT_SHA=\"$KEEPSECRET_COMMIT_SHA\"" "$KEEPSECRET_PROVENANCE_PATH" >/dev/null || {
        die "keepsecret provenance does not record expected commit"
      }
      ;;
    *)
      die "LABWC_INSTALL_METHOD must be 'source' or 'artifact', found '${LABWC_INSTALL_METHOD:-}'"
      ;;
  esac
  assert_binary_dependencies "$KEEPSECRET_BIN_PATH" "keepsecret"
}

verify_kirigami_runtime_install() {
  local qml_qmldir=""
  local runtime_library=""

  [[ "${LABWC_INSTALL_METHOD:-}" == "source" ]] || return 0

  require_file "$KIRIGAMI_RUNTIME_PROVENANCE_PATH"
  grep -F "KIRIGAMI_REPO_URL=\"$KIRIGAMI_REPO_URL\"" "$KIRIGAMI_RUNTIME_PROVENANCE_PATH" >/dev/null || {
    die "Kirigami runtime provenance does not record expected repo URL"
  }
  grep -F "KIRIGAMI_REPO_COMMIT=\"$KIRIGAMI_REPO_COMMIT\"" "$KIRIGAMI_RUNTIME_PROVENANCE_PATH" >/dev/null || {
    die "Kirigami runtime provenance does not record expected commit"
  }
  grep -F "KIRIGAMI_VERSION=\"$KIRIGAMI_VERSION\"" "$KIRIGAMI_RUNTIME_PROVENANCE_PATH" >/dev/null || {
    die "Kirigami runtime provenance does not record expected pinned version"
  }

  qml_qmldir="$(find /usr/local -type f \( -path '*/qt6/qml/org/kde/kirigami/qmldir' -o -path '*/qml/org/kde/kirigami/qmldir' \) | LC_ALL=C sort | head -n 1)"
  [[ -n "$qml_qmldir" ]] || die "Kirigami runtime install is missing the org.kde.kirigami qmldir under /usr/local"
  runtime_library="$(find /usr/local -type f \( -name 'libKirigami*.so*' -o -name 'libKF6Kirigami*.so*' \) | LC_ALL=C sort | head -n 1)"
  [[ -n "$runtime_library" ]] || die "Kirigami runtime install is missing shared libraries under /usr/local"

  if find /usr/local -path '*/cmake/KF6Kirigami*' -o -path '*/include/KF6/Kirigami*' | grep -q .; then
    die "Kirigami development artifacts were left installed under /usr/local"
  fi
}

verify_greeter_contract() {
  require_file "/etc/greetd/config.toml"
  require_file "/etc/greetd/regreet.toml"
  require_file "/etc/greetd/regreet.css"
  require_file "/usr/local/bin/labwc-greeter-session"
  require_file "/usr/local/bin/labwc-greeter-regreet"
  require_file "/etc/labwc-greeter/autostart"
  require_file "/etc/labwc-greeter/rc.xml"
  require_file "/etc/pam.d/greetd"
  require_file "/etc/pam.d/greetd-greeter"
  require_dir "/var/lib/greetd/greeter"
  require_dir "/var/lib/regreet"
  require_dir "/var/log/regreet"
  require_file "$(greeter_log_path)"
  require_file "$(greeter_session_log_path)"

  grep -F '/usr/local/bin/labwc-greeter-session' "/etc/greetd/config.toml" >/dev/null || {
    die "greetd config lost the managed greeter session wrapper"
  }
  grep -F 'dbus-run-session -- /usr/bin/labwc -C /etc/labwc-greeter' "/usr/local/bin/labwc-greeter-session" >/dev/null || {
    die "greeter session wrapper lost the managed dbus-run-session greeter contract"
  }
  grep -F '/usr/local/bin/labwc-greeter-regreet' "/etc/labwc-greeter/autostart" >/dev/null || {
    die "greeter labwc autostart no longer launches the managed regreet wrapper"
  }
  # shellcheck disable=SC2016
  grep -F 'kill -TERM "$LABWC_PID"' "/etc/labwc-greeter/autostart" >/dev/null || {
    die "greeter labwc autostart no longer terminates labwc when regreet exits"
  }
  grep -F 'WAYLAND_DISPLAY=%s' "/usr/local/bin/labwc-greeter-session" >/dev/null || {
    die "greeter session wrapper lost the managed WAYLAND_DISPLAY logging format"
  }
  # shellcheck disable=SC2016
  grep -F 'display_name="$(wait_for_wayland_display)"' "/usr/local/bin/labwc-greeter-regreet" >/dev/null || {
    die "greeter launcher no longer waits for a Wayland display name before starting regreet"
  }
  # shellcheck disable=SC2016
  grep -F 'export WAYLAND_DISPLAY="$display_name"' "/usr/local/bin/labwc-greeter-regreet" >/dev/null || {
    die "greeter launcher no longer exports the resolved WAYLAND_DISPLAY"
  }
  # shellcheck disable=SC2016
  grep -F 'wait_for_wayland_socket "$display_name"' "/usr/local/bin/labwc-greeter-regreet" >/dev/null || {
    die "greeter launcher lost the managed Wayland socket readiness wait"
  }
  grep -F 'sleep 1' "/usr/local/bin/labwc-greeter-regreet" >/dev/null || {
    die "greeter launcher lost the managed post-socket startup delay"
  }
  # shellcheck disable=SC2016
  grep -F 'exec "$regreet_bin" --config "$regreet_config" --style "$regreet_style"' "/usr/local/bin/labwc-greeter-regreet" >/dev/null || {
    die "greeter launcher lost the managed regreet config/style execution path"
  }
  grep -F 'LABWC_UPDATE_ACTIVATION_ENV=1' "/etc/greetd/config.toml" >/dev/null || {
    die "greetd config lost the managed activation-environment contract"
  }
  grep -F 'LIBSEAT_BACKEND=logind' "/etc/greetd/config.toml" >/dev/null || {
    die "greetd config lost the managed logind greeter contract"
  }
  grep -F 'pam_systemd.so type=wayland desktop=labwc' "/etc/pam.d/greetd" >/dev/null || {
    die "managed greetd PAM stack lost pam_systemd metadata"
  }
  grep -F 'pam_systemd.so class=greeter type=wayland desktop=labwc' "/etc/pam.d/greetd-greeter" >/dev/null || {
    die "managed greeter PAM stack lost pam_systemd greeter metadata"
  }

  verify_path_mode "/etc/greetd/config.toml" "root:root:644"
  verify_path_mode "/etc/greetd/regreet.toml" "root:root:644"
  verify_path_mode "/etc/greetd/regreet.css" "root:root:644"
  verify_path_mode "/usr/local/bin/labwc-greeter-session" "root:root:755"
  verify_path_mode "/usr/local/bin/labwc-greeter-regreet" "root:root:755"
  verify_path_mode "/etc/labwc-greeter/autostart" "root:root:755"
  verify_path_mode "/etc/labwc-greeter/rc.xml" "root:root:644"
  verify_path_mode "/var/lib/greetd/greeter" "greeter:greeter:700"
  verify_path_mode "/var/lib/regreet" "greeter:greeter:700"
  verify_path_mode "/var/log/regreet" "greeter:greeter:750"
  verify_path_mode "$(greeter_log_path)" "greeter:greeter:640"
  verify_path_mode "$(greeter_session_log_path)" "greeter:greeter:640"
}

verify_session_activation_contract() {
  local session_entry="/usr/local/bin/labwc-session-start"
  local session_wrapper="/usr/local/bin/labwc-session"
  local session_autostart="$LABWC_TARGET_HOME/.config/labwc/autostart"
  local session_environment="$LABWC_TARGET_HOME/.config/labwc/environment"
  local profile_path="$LABWC_TARGET_HOME/.profile"
  local bashrc_path="$LABWC_TARGET_HOME/.bashrc"
  local zprofile_path="$LABWC_TARGET_HOME/.zprofile"
  local zshrc_path="$LABWC_TARGET_HOME/.zshrc"

  require_file "$session_entry"
  require_file "$session_wrapper"
  require_file "$session_autostart"
  require_file "$session_environment"
  require_file "$profile_path"
  require_file "$bashrc_path"
  require_file "$zprofile_path"
  require_file "$zshrc_path"
  grep -F 'refusing to fall back to dbus-run-session' "$session_entry" >/dev/null || {
    die "labwc-session-start lost the broker-only no-fallback contract"
  }
  grep -F 'DBUS_SESSION_BUS_ADDRESS=' "$session_entry" >/dev/null || {
    die "labwc-session-start lost the managed broker bus export"
  }
  grep -F 'dbus-update-activation-environment --systemd' "$session_autostart" >/dev/null || {
    die "labwc autostart lost the explicit systemd activation-environment handoff"
  }
  # shellcheck disable=SC2016
  grep -F 'dbus-update-activation-environment $dbus_vars' "$session_autostart" >/dev/null || {
    die "labwc autostart lost the explicit D-Bus activation-environment handoff"
  }
  grep -F '/usr/local/lib/x86_64-linux-gnu/qt6/qml' "$session_environment" >/dev/null || {
    die "labwc session environment lost the managed /usr/local Qt QML import precedence"
  }
  grep -F 'QT_PLUGIN_PATH=/usr/local/lib/x86_64-linux-gnu/qt6/plugins' "$session_environment" >/dev/null || {
    die "labwc session environment lost the managed /usr/local Qt plugin path precedence"
  }
  grep -F '.config/system/profile.d/00-build-env.sh' "$profile_path" >/dev/null || {
    die ".profile lost the managed 00-system environment source hook"
  }
  grep -F 'path_prepend_unique' "$profile_path" >/dev/null || {
    die ".profile lost the managed PATH deduplication helper"
  }
  if grep -Eq '(^|[[:space:]])export[[:space:]]+PATH=' "$bashrc_path"; then
    die ".bashrc must not export PATH; PATH belongs in .profile only"
  fi
  if grep -Eq '(^|[[:space:]])export[[:space:]]+PATH=' "$zprofile_path"; then
    die ".zprofile must not export PATH; PATH belongs in .profile only"
  fi
  if grep -Eq '(^|[[:space:]])export[[:space:]]+PATH=' "$zshrc_path"; then
    die ".zshrc must not export PATH; PATH belongs in .profile only"
  fi
}

verify_structured_config_files() {
  local -a config_files=(
    "/etc/greetd/config.toml"
    "/etc/greetd/regreet.toml"
    "/etc/labwc-greeter/rc.xml"
    "/usr/share/wayland-sessions/labwc.desktop"
    "$LABWC_TARGET_HOME/.config/labwc/rc.xml"
    "$LABWC_TARGET_HOME/.config/labwc/menu.xml"
    "$LABWC_TARGET_HOME/.config/Thunar/uca.xml"
    "$LABWC_TARGET_HOME/.config/waybar/config.jsonc"
  )
  local config_path

  for config_path in "${config_files[@]}"; do
    require_file "$config_path"
  done

  python3 - "${config_files[@]}" <<'PY'
from pathlib import Path
import configparser
import json
import re
import sys
import tomllib
import xml.etree.ElementTree as ET

allowed_literals = {"@DEFAULT_AUDIO_SINK@"}

for raw_path in sys.argv[1:]:
    path = Path(raw_path)
    text = path.read_text(encoding="utf-8")
    unresolved = {
        token
        for token in re.findall(r"@[A-Z0-9_]+@", text)
        if token not in allowed_literals
    }
    if unresolved:
        raise SystemExit(
            f"{path} still contains unresolved placeholders: {', '.join(sorted(unresolved))}"
        )

    if path.suffix == ".toml":
        tomllib.loads(text)
    elif path.suffix == ".xml":
        ET.fromstring(text)
    elif path.suffix == ".desktop":
        parser = configparser.ConfigParser(interpolation=None, strict=False)
        parser.read_string(text)
    elif path.name == "config.jsonc":
        json.loads(text)
PY
}

verify_shell_and_units() {
  dash -n "$LABWC_TARGET_HOME/.config/labwc/autostart"
  sh -n "/etc/labwc-greeter/autostart"
  sh -n "/usr/local/bin/labwc-greeter-session"
  sh -n "/usr/local/bin/labwc-greeter-regreet"
  sh -n "/usr/local/bin/labwc-session-start"
  bash -n "/usr/local/bin/labwc-session"
  systemd-analyze verify \
    /etc/systemd/system/labwc-wireguard-import.service \
    /etc/systemd/system/labwc-vpn-default-off.service >/dev/null
}

verify_install() {
  verify_regreet_install
  verify_labwc_tweaks_install
  verify_keepsecret_install
  verify_kirigami_runtime_install
  verify_greeter_contract
  verify_session_activation_contract
  verify_structured_config_files
  verify_shell_and_units
  log_info "verification completed"
}
