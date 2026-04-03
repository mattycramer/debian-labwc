#!/usr/bin/env bash

verify_regreet_install() {
  require_file "$(regreet_binary_path)"
  require_file "$(regreet_provenance_path)"
  [[ -x "$(regreet_binary_path)" ]] || die "regreet binary is not executable"
  grep -F "REGREET_COMMIT_SHA=\"$REGREET_COMMIT_SHA\"" "$(regreet_provenance_path)" >/dev/null || {
    die "regreet provenance does not record expected commit"
  }
  grep -F "REGREET_RUST_TOOLCHAIN=\"$REGREET_RUST_TOOLCHAIN\"" "$(regreet_provenance_path)" >/dev/null || {
    die "regreet provenance does not record expected rust toolchain"
  }
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
  grep -F "LABWC_TWEAKS_COMMIT_SHA=\"$LABWC_TWEAKS_COMMIT_SHA\"" "$LABWC_TWEAKS_PROVENANCE_PATH" >/dev/null || {
    die "labwc-tweaks provenance does not record expected commit"
  }
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
  grep -F "KEEPSECRET_COMMIT_SHA=\"$KEEPSECRET_COMMIT_SHA\"" "$KEEPSECRET_PROVENANCE_PATH" >/dev/null || {
    die "keepsecret provenance does not record expected commit"
  }
  assert_binary_dependencies "$KEEPSECRET_BIN_PATH" "keepsecret"
}

verify_greeter_contract() {
  require_file "/etc/greetd/config.toml"
  require_file "/usr/local/bin/labwc-greeter-session"
  require_file "/usr/local/bin/labwc-greeter-regreet"
  require_file "/etc/pam.d/greetd"
  require_file "/etc/pam.d/greetd-greeter"
  require_dir "/var/lib/regreet"
  require_dir "/var/log/regreet"

  grep -F 'dbus-run-session -- /usr/bin/labwc' "/etc/greetd/config.toml" >/dev/null || {
    die "greetd config lost the managed dbus-run-session greeter contract"
  }
  grep -F '/usr/local/bin/labwc-greeter-session' "/etc/greetd/config.toml" >/dev/null || {
    die "greetd config lost the managed greeter session wrapper"
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

  stat -c '%U:%G:%a' /var/lib/regreet | grep -Fx 'greeter:greeter:700' >/dev/null || {
    die "/var/lib/regreet has unexpected ownership or mode"
  }
  stat -c '%U:%G:%a' /var/log/regreet | grep -Fx 'greeter:greeter:750' >/dev/null || {
    die "/var/log/regreet has unexpected ownership or mode"
  }
}

verify_session_activation_contract() {
  local session_entry="/usr/local/bin/labwc-session-start"
  local session_wrapper="/usr/local/bin/labwc-session"
  local session_autostart="$LABWC_TARGET_HOME/.config/labwc/autostart"

  require_file "$session_entry"
  require_file "$session_wrapper"
  require_file "$session_autostart"
  grep -F 'refusing to fall back to dbus-run-session' "$session_entry" >/dev/null || {
    die "labwc-session-start lost the broker-only no-fallback contract"
  }
  grep -F 'DBUS_SESSION_BUS_ADDRESS=' "$session_entry" >/dev/null || {
    die "labwc-session-start lost the managed broker bus export"
  }
  grep -F 'dbus-update-activation-environment --systemd' "$session_autostart" >/dev/null || {
    die "labwc autostart lost the explicit systemd activation-environment handoff"
  }
  grep -F 'dbus-update-activation-environment $dbus_vars' "$session_autostart" >/dev/null || {
    die "labwc autostart lost the explicit D-Bus activation-environment handoff"
  }
}

verify_shell_and_units() {
  dash -n "$LABWC_TARGET_HOME/.config/labwc/autostart"
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
  verify_greeter_contract
  verify_session_activation_contract
  verify_shell_and_units
  log_info "verification completed"
}
