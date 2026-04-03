#!/usr/bin/env bash

managed_profile_env_path() {
  printf '%s\n' "$SYSTEM_TARGET_HOME/.config/system/profile.d/00-build-env.sh"
}

managed_npmrc_path() {
  printf '%s\n' "$SYSTEM_TARGET_HOME/.npmrc"
}

managed_pnpmrc_path() {
  printf '%s\n' "$SYSTEM_TARGET_HOME/.config/pnpm/rc"
}

managed_pip_conf_path() {
  printf '%s\n' "$SYSTEM_TARGET_HOME/.config/pip/pip.conf"
}

managed_maven_settings_path() {
  printf '%s\n' "$SYSTEM_TARGET_HOME/.m2/settings.xml"
}

write_home_file() {
  local destination="$1"
  local mode="$2"
  local content="$3"

  run_cmd install -D -m "$mode" -o "$SYSTEM_TARGET_USER" -g "$SYSTEM_TARGET_GROUP" /dev/null "$destination"
  printf '%s' "$content" >"$destination"
  run_cmd chown "$SYSTEM_TARGET_USER:$SYSTEM_TARGET_GROUP" "$destination"
  run_cmd chmod "$mode" "$destination"
}

render_profile_env_content() {
  cat <<'EOF'
# Managed by 00-system
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"

export EDITOR="nano"
export VISUAL="nano"

export RUSTUP_HOME="/pool/builds/rust/rustup"
export CARGO_HOME="/pool/builds/rust/cargo"
export CARGO_TARGET_DIR="/pool/builds/rust/target"

export GOPATH="/pool/builds/go"
export GOBIN="/pool/builds/go/bin"
export GOCACHE="/pool/cache/go/build"
export GOMODCACHE="/pool/cache/go/mod"

export PIP_CACHE_DIR="/pool/cache/pip"
export PYTHONPYCACHEPREFIX="/pool/cache/python/pycache"
export PIPX_HOME="/pool/builds/python/pipx"
export PIPX_BIN_DIR="$HOME/.local/bin"
export PIPX_MAN_DIR="$HOME/.local/share/man"
export WORKON_HOME="/pool/builds/python/virtualenvs"
export PIPENV_CACHE_DIR="/pool/cache/pipenv"
export POETRY_CACHE_DIR="/pool/cache/pypoetry"
export POETRY_DATA_DIR="/pool/builds/pypoetry/data"
export POETRY_VIRTUALENVS_PATH="/pool/builds/python/poetry-virtualenvs"
export POETRY_PYTHON_INSTALLATION_DIR="/pool/builds/pypoetry/python"
export UV_CACHE_DIR="/pool/cache/uv"
export UV_TOOL_DIR="/pool/builds/uv/tools"
export UV_TOOL_BIN_DIR="/pool/builds/uv/bin"
export UV_PYTHON_INSTALL_DIR="/pool/builds/uv/python"

export PNPM_HOME="/pool/builds/node_modules/pnpm/bin"
export COREPACK_HOME="/pool/cache/corepack"
export YARN_CACHE_FOLDER="/pool/cache/yarn"
export YARN_GLOBAL_FOLDER="/pool/builds/node_modules/yarn/global"

export MAVEN_USER_HOME="/pool/builds/maven"
export GRADLE_USER_HOME="/pool/cache/gradle"
export SBT_GLOBAL_BASE="/pool/builds/sbt"
export SBT_BOOT_DIR="/pool/cache/sbt/boot"
export SBT_IVY_HOME="/pool/cache/ivy"
export COURSIER_CACHE="/pool/cache/coursier"

export DOTNET_CLI_HOME="/pool/builds/dotnet/cli"
export NUGET_PACKAGES="/pool/cache/nuget/packages"
export NUGET_HTTP_CACHE_PATH="/pool/cache/nuget/http"
export NUGET_PLUGINS_CACHE_PATH="/pool/cache/nuget/plugins-cache"

export GEM_HOME="/pool/builds/ruby/gems"
export GEM_SPEC_CACHE="/pool/cache/rubygems"
export BUNDLE_USER_HOME="/pool/builds/bundle/home"
export BUNDLE_USER_CACHE="/pool/cache/bundle"
export BUNDLE_USER_CONFIG="$HOME/.config/bundle"
export BUNDLE_USER_PLUGIN="/pool/builds/bundle/plugins"

export COMPOSER_HOME="/pool/builds/composer"
export COMPOSER_CACHE_DIR="/pool/cache/composer"
EOF
}

render_npmrc_content() {
  cat <<'EOF'
cache=/pool/cache/npm
prefix=/pool/builds/node_modules/npm
EOF
}

render_pnpmrc_content() {
  cat <<'EOF'
cache-dir=/pool/cache/pnpm/cache
global-bin-dir=/pool/builds/node_modules/pnpm/bin
global-dir=/pool/builds/node_modules/pnpm/global
state-dir=/pool/cache/pnpm/state
store-dir=/pool/cache/pnpm/store
EOF
}

render_pip_conf_content() {
  cat <<'EOF'
[global]
cache-dir = /pool/cache/pip
EOF
}

render_maven_settings_content() {
  cat <<'EOF'
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 https://maven.apache.org/xsd/settings-1.0.0.xsd">
  <localRepository>/pool/cache/maven/repository</localRepository>
</settings>
EOF
}

apply_home_environment() {
  write_home_file "$(managed_profile_env_path)" 0644 "$(render_profile_env_content)"
  write_home_file "$(managed_npmrc_path)" 0644 "$(render_npmrc_content)"
  write_home_file "$(managed_pnpmrc_path)" 0644 "$(render_pnpmrc_content)"
  write_home_file "$(managed_pip_conf_path)" 0644 "$(render_pip_conf_content)"
  write_home_file "$(managed_maven_settings_path)" 0644 "$(render_maven_settings_content)"
}

remove_home_environment() {
  remove_if_present "$(managed_profile_env_path)"
  remove_if_present "$(managed_npmrc_path)"
  remove_if_present "$(managed_pnpmrc_path)"
  remove_if_present "$(managed_pip_conf_path)"
  remove_if_present "$(managed_maven_settings_path)"
}

verify_home_environment() {
  require_file "$(managed_profile_env_path)"
  require_file "$(managed_npmrc_path)"
  require_file "$(managed_pnpmrc_path)"
  require_file "$(managed_pip_conf_path)"
  require_file "$(managed_maven_settings_path)"

  grep -F 'export RUSTUP_HOME="/pool/builds/rust/rustup"' "$(managed_profile_env_path)" >/dev/null || {
    die "managed profile env file is missing RUSTUP_HOME"
  }
  grep -F 'export CARGO_HOME="/pool/builds/rust/cargo"' "$(managed_profile_env_path)" >/dev/null || {
    die "managed profile env file is missing CARGO_HOME"
  }
  grep -F 'export CARGO_TARGET_DIR="/pool/builds/rust/target"' "$(managed_profile_env_path)" >/dev/null || {
    die "managed profile env file is missing CARGO_TARGET_DIR"
  }
  grep -F 'export GOPATH="/pool/builds/go"' "$(managed_profile_env_path)" >/dev/null || {
    die "managed profile env file is missing GOPATH"
  }
  grep -F 'export GOCACHE="/pool/cache/go/build"' "$(managed_profile_env_path)" >/dev/null || {
    die "managed profile env file is missing GOCACHE"
  }
  grep -F 'prefix=/pool/builds/node_modules/npm' "$(managed_npmrc_path)" >/dev/null || {
    die "managed .npmrc is missing the expected prefix"
  }
  grep -F 'cache=/pool/cache/npm' "$(managed_npmrc_path)" >/dev/null || {
    die "managed .npmrc is missing the expected cache"
  }
  grep -F 'global-dir=/pool/builds/node_modules/pnpm/global' "$(managed_pnpmrc_path)" >/dev/null || {
    die "managed pnpm rc is missing the expected global-dir"
  }
  grep -F 'store-dir=/pool/cache/pnpm/store' "$(managed_pnpmrc_path)" >/dev/null || {
    die "managed pnpm rc is missing the expected store-dir"
  }
  grep -F 'cache-dir = /pool/cache/pip' "$(managed_pip_conf_path)" >/dev/null || {
    die "managed pip config is missing the expected cache-dir"
  }
  grep -F '<localRepository>/pool/cache/maven/repository</localRepository>' "$(managed_maven_settings_path)" >/dev/null || {
    die "managed Maven settings file is missing the expected localRepository"
  }
}
