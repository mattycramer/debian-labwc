#!/usr/bin/env bash

readonly SYSTEM_SECURE_BOOT_CN="Labwc Secure Boot"
readonly SYSTEM_SECURE_BOOT_COUNTRY="SE"
readonly SYSTEM_SECURE_BOOT_STATE="Skane"
readonly SYSTEM_SECURE_BOOT_LOCALITY="Malmo"
readonly SYSTEM_SECURE_BOOT_ORGANIZATION="Matthew Cramer"
readonly SYSTEM_SECURE_BOOT_ORG_UNIT="Personal"
readonly SYSTEM_SECURE_BOOT_EMAIL="contact@jcramer.sbs"
readonly SYSTEM_SECURE_BOOT_KEY_BITS="4096"
readonly SYSTEM_SECURE_BOOT_VALID_DAYS="36500"
readonly SYSTEM_SECURE_BOOT_DIR="/var/lib/shim-signed/labwc-secure-boot"
readonly SYSTEM_SECURE_BOOT_KEY_PATH="${SYSTEM_SECURE_BOOT_DIR}/MOK.priv"
readonly SYSTEM_SECURE_BOOT_CERT_PATH="${SYSTEM_SECURE_BOOT_DIR}/MOK.der"
readonly SYSTEM_SECURE_BOOT_OPENSSL_CONFIG_PATH="${SYSTEM_SECURE_BOOT_DIR}/openssl.cnf"
readonly SYSTEM_SECURE_BOOT_CONFIG_DIR="/etc/labwc-secure-boot"
readonly SYSTEM_SECURE_BOOT_MODULES_CONFIG_PATH="${SYSTEM_SECURE_BOOT_CONFIG_DIR}/modules.conf"
readonly SYSTEM_SECURE_BOOT_MODULES_TEMPLATE_PATH="${SCRIPT_DIR}/secureboot.modules.conf"
readonly SYSTEM_SECURE_BOOT_TOOL_DIR="/usr/local/libexec/labwc-secure-boot"
readonly SYSTEM_SECURE_BOOT_TOOL_PATH="${SYSTEM_SECURE_BOOT_TOOL_DIR}/tool"
readonly SYSTEM_SECURE_BOOT_TOOL_MODE="0755"
readonly SYSTEM_CUSTOM_MODULE_SOURCE_ROOT="/usr/local/src/labwc-kmods"
readonly SYSTEM_CUSTOM_MODULE_BUILD_ROOT="/var/cache/labwc-secure-boot/build"
readonly SYSTEM_DKMS_CONF_DIR="/etc/dkms/framework.conf.d"
readonly SYSTEM_DKMS_CONF_PATH="${SYSTEM_DKMS_CONF_DIR}/90-labwc-secure-boot.conf"
readonly SYSTEM_DKMS_CONF_MODE="0644"
readonly SYSTEM_SIGN_MODULE_HELPER="/usr/local/bin/sign-module"
readonly SYSTEM_SIGN_MODULE_HELPER_MODE="0755"
readonly SYSTEM_KERNEL_POSTINST_HOOK_PATH="/etc/kernel/postinst.d/zz-labwc-secure-boot"
readonly SYSTEM_KERNEL_HEADER_POSTINST_HOOK_DIR="/etc/kernel/header_postinst.d"
readonly SYSTEM_KERNEL_HEADER_POSTINST_HOOK_PATH="${SYSTEM_KERNEL_HEADER_POSTINST_HOOK_DIR}/zz-labwc-secure-boot"
readonly SYSTEM_KERNEL_HOOK_MODE="0755"
readonly SYSTEM_SECURE_BOOT_DIR_MODE="0700"
readonly SYSTEM_SECURE_BOOT_FILE_MODE="0600"
readonly SYSTEM_SECURE_BOOT_CONFIG_MODE="0644"
readonly SYSTEM_SECURE_BOOT_PACKAGES=(
  build-essential
  kmod
  mokutil
  openssl
  shim-signed
  xz-utils
  zstd
)

secure_boot_package_installed() {
  dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null | grep -Fx 'install ok installed' >/dev/null 2>&1
}

secure_boot_apt_update() {
  log_info "updating apt metadata for Secure Boot dependencies"
  run_cmd env \
    DEBIAN_FRONTEND=noninteractive \
    APT_LISTCHANGES_FRONTEND=none \
    apt-get update \
      -o Acquire::Retries=3 \
      -o Acquire::http::Timeout=20
}

ensure_secure_boot_packages() {
  local package=""
  local package_list=""
  local -a missing_packages=()

  for package in "${SYSTEM_SECURE_BOOT_PACKAGES[@]}"; do
    if ! secure_boot_package_installed "$package"; then
      missing_packages+=("$package")
    fi
  done

  if ((${#missing_packages[@]} == 0)); then
    return 0
  fi

  secure_boot_apt_update
  package_list="$(printf '%s ' "${missing_packages[@]}")"
  package_list="${package_list% }"
  log_info "installing Secure Boot dependency set: ${package_list}"
  run_cmd env \
    DEBIAN_FRONTEND=noninteractive \
    APT_LISTCHANGES_FRONTEND=none \
    apt-get install \
      -y \
      -V \
      --no-install-recommends \
      -o DPkg::Lock::Timeout=60 \
      "${missing_packages[@]}"
}

require_secure_boot_runtime() {
  require_command mokutil
  require_command openssl
  [[ -d /sys/firmware/efi ]] || die "Secure Boot MOK management requires a UEFI boot; /sys/firmware/efi is not present"
  [[ -d /sys/firmware/efi/efivars ]] || die "Secure Boot MOK management requires EFI variable access; /sys/firmware/efi/efivars is not present"
}

log_secure_boot_state() {
  local state=""
  state="$(mokutil --sb-state 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/[[:space:]]$//')"
  [[ -n "$state" ]] || die "could not determine Secure Boot state via mokutil --sb-state"

  case "$state" in
    *"disabled"*)
      log_warn "$state; MOK enrollment will still be queued for the next reboot"
      ;;
    *)
      log_info "$state"
      ;;
  esac
}

render_managed_secure_boot_openssl_config() {
  cat <<EOF
[ req ]
default_bits = ${SYSTEM_SECURE_BOOT_KEY_BITS}
default_md = sha256
prompt = no
distinguished_name = dn
x509_extensions = v3_labwc_secure_boot

[ dn ]
C = ${SYSTEM_SECURE_BOOT_COUNTRY}
ST = ${SYSTEM_SECURE_BOOT_STATE}
L = ${SYSTEM_SECURE_BOOT_LOCALITY}
O = ${SYSTEM_SECURE_BOOT_ORGANIZATION}
OU = ${SYSTEM_SECURE_BOOT_ORG_UNIT}
CN = ${SYSTEM_SECURE_BOOT_CN}
emailAddress = ${SYSTEM_SECURE_BOOT_EMAIL}

[ v3_labwc_secure_boot ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning,1.3.6.1.4.1.2312.16.1.2
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF
}

build_secure_boot_tool_candidate() {
  local destination_path="$1"

  cat >"$destination_path" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=\$'\\n\\t'
shopt -s nullglob

readonly LABWC_MOK_KEY="${SYSTEM_SECURE_BOOT_KEY_PATH}"
readonly LABWC_MOK_CERT="${SYSTEM_SECURE_BOOT_CERT_PATH}"
readonly LABWC_MODULES_CONF="${SYSTEM_SECURE_BOOT_MODULES_CONFIG_PATH}"
readonly LABWC_DKMS_TREE="/var/lib/dkms"
readonly LABWC_DKMS_CONFIG_ROOT="/etc/dkms"
readonly LABWC_DKMS_OVERRIDE_SCRIPT="labwc-secure-boot-dkms-post-install"
readonly LABWC_CUSTOM_MODULE_SOURCE_ROOT="${SYSTEM_CUSTOM_MODULE_SOURCE_ROOT}"
readonly LABWC_CUSTOM_MODULE_BUILD_ROOT="${SYSTEM_CUSTOM_MODULE_BUILD_ROOT}"
readonly LABWC_SIGNER_CN="${SYSTEM_SECURE_BOOT_CN}"
readonly LABWC_TOOL_PATH="${SYSTEM_SECURE_BOOT_TOOL_PATH}"

declare -A CHANGED_KERNELS=()
declare -a DKMS_ALLOWLIST=()
declare -a MODULE_GLOBS=()
AUTO_CUSTOM_DKMS=yes

die() {
  printf 'ERROR: %s\\n' "\$*" >&2
  exit 1
}

log_info() {
  printf 'INFO: %s\\n' "\$*" >&2
}

log_warn() {
  printf 'WARN: %s\\n' "\$*" >&2
}

require_command() {
  command -v "\$1" >/dev/null 2>&1 || die "missing command: \$1"
}

require_file() {
  [[ -f "\$1" ]] || die "missing file: \$1"
}

normalize_fingerprint() {
  tr '[:upper:]' '[:lower:]' | tr -d '[:space:]:'
}

parse_config_value() {
  local raw="\$1"
  local line_number="\$2"
  local value=""

  case "\$raw" in
    \"*\")
      [[ "\${#raw}" -ge 2 && "\${raw: -1}" == '"' ]] || die "invalid quoted value on line \$line_number in \$LABWC_MODULES_CONF"
      value="\${raw:1:\${#raw}-2}"
      ;;
    \'*\')
      [[ "\${#raw}" -ge 2 && "\${raw: -1}" == "'" ]] || die "invalid quoted value on line \$line_number in \$LABWC_MODULES_CONF"
      value="\${raw:1:\${#raw}-2}"
      ;;
    *)
      [[ "\$raw" != *[[:space:]]* ]] || die "unquoted whitespace is not allowed on line \$line_number in \$LABWC_MODULES_CONF"
      value="\$raw"
      ;;
  esac

  [[ "\$value" != *'\$('* ]] || die "command substitution is not allowed on line \$line_number in \$LABWC_MODULES_CONF"
  [[ "\$value" != *'\`'* ]] || die "backticks are not allowed on line \$line_number in \$LABWC_MODULES_CONF"
  [[ "\$value" != *'\${'* ]] || die "parameter expansion is not allowed on line \$line_number in \$LABWC_MODULES_CONF"

  printf '%s' "\$value"
}

load_modules_config() {
  local line=""
  local line_number=0
  local key=""
  local raw_value=""
  local value=""

  AUTO_CUSTOM_DKMS=yes
  DKMS_ALLOWLIST=()
  MODULE_GLOBS=()

  [[ -f "\$LABWC_MODULES_CONF" ]] || return 0

  while IFS= read -r line || [[ -n "\$line" ]]; do
    line_number=\$((line_number + 1))
    line="\${line%\$'\\r'}"
    [[ "\$line" =~ ^[[:space:]]*(\$|#) ]] && continue
    [[ "\$line" =~ ^([A-Z_]+)=(.*)\$ ]] || die "invalid config assignment on line \$line_number in \$LABWC_MODULES_CONF"
    key="\${BASH_REMATCH[1]}"
    raw_value="\${BASH_REMATCH[2]}"
    value="\$(parse_config_value "\$raw_value" "\$line_number")"

    case "\$key" in
      AUTO_CUSTOM_DKMS)
        case "\$value" in
          yes|no) AUTO_CUSTOM_DKMS="\$value" ;;
          *) die "AUTO_CUSTOM_DKMS must be yes or no on line \$line_number in \$LABWC_MODULES_CONF" ;;
        esac
        ;;
      DKMS_ALLOW)
        [[ "\$value" =~ ^[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)?\$ ]] || die "invalid DKMS_ALLOW value on line \$line_number in \$LABWC_MODULES_CONF"
        DKMS_ALLOWLIST+=("\$value")
        ;;
      MODULE_GLOB)
        [[ "\$value" == /* ]] || die "MODULE_GLOB must be absolute on line \$line_number in \$LABWC_MODULES_CONF"
        MODULE_GLOBS+=("\$value")
        ;;
      *)
        die "unsupported config key '\$key' on line \$line_number in \$LABWC_MODULES_CONF"
        ;;
    esac
  done <"\$LABWC_MODULES_CONF"
}

resolve_modinfo_bin() {
  local candidate=""
  for candidate in /usr/sbin/modinfo /usr/bin/modinfo /sbin/modinfo; do
    if [[ -x "\$candidate" ]]; then
      printf '%s' "\$candidate"
      return 0
    fi
  done

  candidate="\$(command -v modinfo 2>/dev/null || true)"
  [[ -n "\$candidate" ]] || die "could not locate modinfo"
  printf '%s' "\$candidate"
}

resolve_depmod_bin() {
  local candidate=""
  for candidate in /usr/sbin/depmod /usr/bin/depmod /sbin/depmod; do
    if [[ -x "\$candidate" ]]; then
      printf '%s' "\$candidate"
      return 0
    fi
  done

  candidate="\$(command -v depmod 2>/dev/null || true)"
  [[ -n "\$candidate" ]] || die "could not locate depmod"
  printf '%s' "\$candidate"
}

managed_cert_fingerprint() {
  local fingerprint=""

  fingerprint="\$(openssl x509 -inform DER -in "\$LABWC_MOK_CERT" -noout -fingerprint -sha1 2>/dev/null)" || {
    die "could not read fingerprint for \$LABWC_MOK_CERT"
  }
  printf '%s' "\${fingerprint##*=}" | normalize_fingerprint
}

verify_managed_keypair() {
  local key_public=""
  local cert_public=""

  require_file "\$LABWC_MOK_KEY"
  require_file "\$LABWC_MOK_CERT"
  openssl pkey -in "\$LABWC_MOK_KEY" -passin pass: -noout >/dev/null 2>&1 || die "managed Secure Boot key is unreadable or encrypted: \$LABWC_MOK_KEY"
  openssl x509 -inform DER -in "\$LABWC_MOK_CERT" -noout >/dev/null 2>&1 || die "managed Secure Boot certificate is not valid DER: \$LABWC_MOK_CERT"
  key_public="\$(openssl pkey -in "\$LABWC_MOK_KEY" -passin pass: -pubout -outform PEM 2>/dev/null)" || die "could not read public key from \$LABWC_MOK_KEY"
  cert_public="\$(openssl x509 -inform DER -in "\$LABWC_MOK_CERT" -pubkey -noout 2>/dev/null)" || die "could not read public certificate key from \$LABWC_MOK_CERT"
  [[ "\$key_public" == "\$cert_public" ]] || die "managed Secure Boot key and certificate do not match"
}

module_compression_kind() {
  case "\$1" in
    *.ko) printf '%s' none ;;
    *.ko.gz) printf '%s' gzip ;;
    *.ko.xz) printf '%s' xz ;;
    *.ko.zst) printf '%s' zstd ;;
    *) die "unsupported module path suffix: \$1" ;;
  esac
}

resolve_module_kernelver() {
  local module_path="\$1"
  local modinfo_bin=""
  local vermagic=""

  modinfo_bin="\$(resolve_modinfo_bin)"
  vermagic="\$("\$modinfo_bin" -F vermagic "\$module_path" 2>/dev/null || true)"
  [[ -n "\$vermagic" ]] || die "could not determine kernel version from module vermagic: \$module_path"
  printf '%s' "\${vermagic%% *}"
}

resolve_module_sig_hash() {
  local kernelver="\$1"
  local config_path=""
  local hash=""

  for config_path in \
    "/lib/modules/\$kernelver/build/include/config/auto.conf" \
    "/lib/modules/\$kernelver/build/.config" \
    "/boot/config-\$kernelver"; do
    [[ -f "\$config_path" ]] || continue
    hash="\$(awk -F= '/^CONFIG_MODULE_SIG_HASH=/{ gsub(/"/, "", \$2); print \$2; exit }' "\$config_path")"
    if [[ -n "\$hash" ]]; then
      printf '%s' "\$hash"
      return 0
    fi
  done

  die "could not determine CONFIG_MODULE_SIG_HASH for kernel \$kernelver"
}

resolve_sign_file() {
  local kernelver="\$1"
  local short_kernelver=""
  local candidate=""

  short_kernelver="\${kernelver%.*}"
  for candidate in \
    "/lib/modules/\$kernelver/build/scripts/sign-file" \
    "/usr/lib/linux-kbuild-\$short_kernelver/scripts/sign-file"; do
    if [[ -x "\$candidate" ]]; then
      printf '%s' "\$candidate"
      return 0
    fi
  done

  die "could not locate sign-file for kernel \$kernelver"
}

decompress_module_copy() {
  local module_path="\$1"
  local output_path="\$2"
  local kind=""

  kind="\$(module_compression_kind "\$module_path")"
  case "\$kind" in
    none)
      cp -f -- "\$module_path" "\$output_path"
      ;;
    gzip)
      gzip -d -c -- "\$module_path" >"\$output_path"
      ;;
    xz)
      xz -d -c -- "\$module_path" >"\$output_path"
      ;;
    zstd)
      zstd -d -q -c -- "\$module_path" >"\$output_path"
      ;;
    *)
      die "unsupported module compression kind: \$kind"
      ;;
  esac
}

recompress_module_copy() {
  local kind="\$1"
  local input_path="\$2"
  local output_path="\$3"

  case "\$kind" in
    none)
      cp -f -- "\$input_path" "\$output_path"
      ;;
    gzip)
      gzip -n -9 -c -- "\$input_path" >"\$output_path"
      ;;
    xz)
      xz -z -c -- "\$input_path" >"\$output_path"
      ;;
    zstd)
      zstd -q -f -c -- "\$input_path" >"\$output_path"
      ;;
    *)
      die "unsupported module compression kind: \$kind"
      ;;
  esac
}

module_signer() {
  local modinfo_bin=""
  modinfo_bin="\$(resolve_modinfo_bin)"
  "\$modinfo_bin" -F signer "\$1" 2>/dev/null || true
}

module_sig_key() {
  local modinfo_bin=""
  modinfo_bin="\$(resolve_modinfo_bin)"
  "\$modinfo_bin" -F sig_key "\$1" 2>/dev/null || true
}

module_is_labwc_signed() {
  local module_path="\$1"
  local signer=""
  local sig_key=""
  local expected_sig_key=""

  signer="\$(module_signer "\$module_path")"
  sig_key="\$(module_sig_key "\$module_path" | normalize_fingerprint)"
  expected_sig_key="\$(managed_cert_fingerprint)"

  [[ "\$signer" == "\$LABWC_SIGNER_CN" && -n "\$sig_key" && "\$sig_key" == "\$expected_sig_key" ]]
}

mark_kernel_for_depmod() {
  local kernelver="\$1"
  CHANGED_KERNELS["\$kernelver"]=1
}

sign_module_in_place() {
  local module_path="\$1"
  local resolved_module=""
  local compression_kind=""
  local kernelver=""
  local sign_hash=""
  local sign_file=""
  local owner=""
  local group=""
  local mode=""
  local tmpdir=""
  local tmp_module=""
  local tmp_output=""

  resolved_module="\$(readlink -f -- "\$module_path")"
  [[ -n "\$resolved_module" && -f "\$resolved_module" ]] || die "missing module file: \$module_path"
  compression_kind="\$(module_compression_kind "\$resolved_module")"

  if module_is_labwc_signed "\$resolved_module"; then
    log_info "module already signed with managed Labwc key: \$resolved_module"
    return 0
  fi

  kernelver="\$(resolve_module_kernelver "\$resolved_module")"
  sign_hash="\$(resolve_module_sig_hash "\$kernelver")"
  sign_file="\$(resolve_sign_file "\$kernelver")"
  owner="\$(stat -c '%u' "\$resolved_module")"
  group="\$(stat -c '%g' "\$resolved_module")"
  mode="\$(stat -c '%a' "\$resolved_module")"
  tmpdir="\$(mktemp -d)"
  tmp_module="\$tmpdir/module.ko"
  case "\$compression_kind" in
    none) tmp_output="\$tmpdir/output.ko" ;;
    gzip) tmp_output="\$tmpdir/output.ko.gz" ;;
    xz) tmp_output="\$tmpdir/output.ko.xz" ;;
    zstd) tmp_output="\$tmpdir/output.ko.zst" ;;
    *) die "unsupported module compression kind: \$compression_kind" ;;
  esac
  trap 'rm -rf -- "\$tmpdir"' RETURN

  decompress_module_copy "\$resolved_module" "\$tmp_module"
  "\$sign_file" "\$sign_hash" "\$LABWC_MOK_KEY" "\$LABWC_MOK_CERT" "\$tmp_module"
  recompress_module_copy "\$compression_kind" "\$tmp_module" "\$tmp_output"
  chown "\$owner:\$group" "\$tmp_output"
  chmod "\$mode" "\$tmp_output"
  touch -r "\$resolved_module" "\$tmp_output"
  mv -f -- "\$tmp_output" "\$resolved_module"

  if [[ "\$resolved_module" == "/lib/modules/\$kernelver/"* ]]; then
    mark_kernel_for_depmod "\$kernelver"
  fi

  rm -rf -- "\$tmpdir"
  trap - RETURN
  log_info "signed \$resolved_module for kernel \$kernelver"
}

run_depmod_for_changed_kernels() {
  local depmod_bin=""
  local kernelver=""

  ((\${#CHANGED_KERNELS[@]} > 0)) || return 0
  depmod_bin="\$(resolve_depmod_bin)"
  for kernelver in "\${!CHANGED_KERNELS[@]}"; do
    log_info "running depmod for kernel \$kernelver"
    "\$depmod_bin" "\$kernelver"
  done
}

dkms_allowlist_matches() {
  local module="\$1"
  local module_version="\$2"
  local entry=""

  for entry in "\${DKMS_ALLOWLIST[@]}"; do
    case "\$entry" in
      "\$module"|"\$module/\$module_version")
        return 0
        ;;
    esac
  done
  return 1
}

path_is_dpkg_owned() {
  local current="\$1"

  [[ -n "\$current" && "\$current" == /* ]] || return 1
  while [[ "\$current" != "/" ]]; do
    if dpkg-query -S -- "\$current" >/dev/null 2>&1; then
      return 0
    fi
    current="\$(dirname -- "\$current")"
  done
  return 1
}

dkms_source_path() {
  local module="\$1"
  local module_version="\$2"
  local source_path=""

  source_path="\$LABWC_DKMS_TREE/\$module/\$module_version/source"
  if [[ -L "\$source_path" || -d "\$source_path" ]]; then
    readlink -f -- "\$source_path"
    return 0
  fi

  source_path="/usr/src/\$module-\$module_version"
  if [[ -d "\$source_path" ]]; then
    readlink -f -- "\$source_path"
    return 0
  fi

  return 1
}

dkms_module_is_managed() {
  local module="\$1"
  local module_version="\$2"
  local source_path=""

  if dkms_allowlist_matches "\$module" "\$module_version"; then
    return 0
  fi

  [[ "\$AUTO_CUSTOM_DKMS" == yes ]] || return 1
  source_path="\$(dkms_source_path "\$module" "\$module_version" 2>/dev/null || true)"
  [[ -n "\$source_path" ]] || return 1
  ! path_is_dpkg_owned "\$source_path"
}

list_dkms_module_versions() {
  local version_path=""
  local module=""
  local module_version=""

  [[ -d "\$LABWC_DKMS_TREE" ]] || return 0
  while IFS= read -r version_path; do
    module_version="\${version_path##*/}"
    module="\${version_path%/*}"
    module="\${module##*/}"
    [[ -n "\$module" && -n "\$module_version" ]] || continue
    printf '%s|%s\\n' "\$module" "\$module_version"
  done < <(find "\$LABWC_DKMS_TREE" -mindepth 2 -maxdepth 2 -type d | LC_ALL=C sort)
}

build_dkms_override_conf_content() {
  local module="\$1"

  cat <<EOF_CONF
# Managed locally. Do not edit manually.
POST_INSTALL="\${LABWC_DKMS_OVERRIDE_SCRIPT} '\${module}' '\\\${module_version}' '\\\${kernelver}' '\\\${arch}'"
EOF_CONF
}

build_dkms_override_script_content() {
  cat <<EOF_SCRIPT
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=\$'\\n\\t'
exec "\${LABWC_TOOL_PATH}" dkms-post-install "\$@"
EOF_SCRIPT
}

install_dkms_override_for_module() {
  local module="\$1"
  local override_dir="\$LABWC_DKMS_CONFIG_ROOT/\$module"
  local conf_path="\$LABWC_DKMS_CONFIG_ROOT/\$module.conf"
  local script_path="\$override_dir/\$LABWC_DKMS_OVERRIDE_SCRIPT"
  local expected_conf=""
  local expected_script=""
  expected_conf="\$(build_dkms_override_conf_content "\$module")"
  expected_script="\$(build_dkms_override_script_content)"

  if [[ -f "\$conf_path" ]]; then
    if ! cmp -s <(printf '%s\\n' "\$expected_conf") "\$conf_path"; then
      die "existing DKMS override at \$conf_path does not match the managed Labwc contract"
    fi
  else
    install -m 0644 -o root -g root /dev/null "\$conf_path"
    printf '%s\\n' "\$expected_conf" >"\$conf_path"
  fi
  chown root:root "\$conf_path"
  chmod 0644 "\$conf_path"

  install -d -m 0755 -o root -g root "\$override_dir"
  if [[ -f "\$script_path" ]]; then
    if ! cmp -s <(printf '%s\\n' "\$expected_script") "\$script_path"; then
      die "existing DKMS override script at \$script_path does not match the managed Labwc contract"
    fi
  else
    install -m 0755 -o root -g root /dev/null "\$script_path"
    printf '%s\\n' "\$expected_script" >"\$script_path"
  fi
  chown root:root "\$script_path"
  chmod 0755 "\$script_path"
}

remove_stale_dkms_overrides() {
  local conf_path=""
  local module=""
  local expected_modules="\$1"
  local override_dir=""
  local script_path=""

  for conf_path in "\$LABWC_DKMS_CONFIG_ROOT"/*.conf; do
    [[ -f "\$conf_path" ]] || continue
    grep -F "POST_INSTALL=\"\${LABWC_DKMS_OVERRIDE_SCRIPT}" "\$conf_path" >/dev/null 2>&1 || continue
    module="\${conf_path##*/}"
    module="\${module%.conf}"
    if grep -Fx "\$module" <<<"\$expected_modules" >/dev/null 2>&1; then
      continue
    fi

    rm -f -- "\$conf_path"
    override_dir="\$LABWC_DKMS_CONFIG_ROOT/\$module"
    script_path="\$override_dir/\$LABWC_DKMS_OVERRIDE_SCRIPT"
    if [[ -f "\$script_path" ]]; then
      if cmp -s <(printf '%s\\n' "\$(build_dkms_override_script_content)") "\$script_path"; then
        rm -f -- "\$script_path"
      fi
    fi
    if [[ -d "\$override_dir" ]] && [[ -z "\$(find "\$override_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
      rmdir -- "\$override_dir"
    fi
  done
}

sync_dkms_overrides() {
  local mode="\$1"
  local module=""
  local module_version=""
  local managed_modules=""
  local expected_module=""
  local override_dir=""
  local conf_path=""
  local script_path=""
  local expected_conf=""
  local expected_script=""

  load_modules_config
  while IFS='|' read -r module module_version; do
    [[ -n "\$module" && -n "\$module_version" ]] || continue
    dkms_module_is_managed "\$module" "\$module_version" || continue
    managed_modules="\${managed_modules}\${module}"$'\\n'
  done < <(list_dkms_module_versions)

  managed_modules="\$(printf '%s' "\$managed_modules" | sed '/^$/d' | LC_ALL=C sort -u)"

  while IFS= read -r expected_module; do
    [[ -n "\$expected_module" ]] || continue
    override_dir="\$LABWC_DKMS_CONFIG_ROOT/\$expected_module"
    conf_path="\$LABWC_DKMS_CONFIG_ROOT/\$expected_module.conf"
    script_path="\$override_dir/\$LABWC_DKMS_OVERRIDE_SCRIPT"
    expected_conf="\$(build_dkms_override_conf_content "\$expected_module")"
    expected_script="\$(build_dkms_override_script_content)"

    case "\$mode" in
      apply)
        install_dkms_override_for_module "\$expected_module"
        ;;
      check)
        [[ -f "\$conf_path" ]] || die "missing DKMS override config for managed module \$expected_module"
        cmp -s <(printf '%s\\n' "\$expected_conf") "\$conf_path" || die "DKMS override config drift detected for \$expected_module"
        [[ -f "\$script_path" ]] || die "missing DKMS override script for managed module \$expected_module"
        cmp -s <(printf '%s\\n' "\$expected_script") "\$script_path" || die "DKMS override script drift detected for \$expected_module"
        ;;
      *)
        die "unsupported DKMS override mode: \$mode"
        ;;
    esac
  done <<<"\$managed_modules"

  case "\$mode" in
    apply)
      remove_stale_dkms_overrides "\$managed_modules"
      ;;
    check)
      for conf_path in "\$LABWC_DKMS_CONFIG_ROOT"/*.conf; do
        [[ -f "\$conf_path" ]] || continue
        grep -F "POST_INSTALL=\"\${LABWC_DKMS_OVERRIDE_SCRIPT}" "\$conf_path" >/dev/null 2>&1 || continue
        module="\${conf_path##*/}"
        module="\${module%.conf}"
        grep -Fx "\$module" <<<"\$managed_modules" >/dev/null 2>&1 || die "stale managed DKMS override remains for module \$module"
      done
      ;;
    *)
      ;;
  esac
}

find_installed_dkms_candidates() {
  local kernelver="\$1"
  local basename="\$2"
  local candidate=""
  local -a candidates=()

  for candidate in \
    "/lib/modules/\$kernelver/updates/dkms/\$basename" \
    "/lib/modules/\$kernelver/extra/\$basename" \
    "/lib/modules/\$kernelver/updates/\$basename"; do
    [[ -f "\$candidate" ]] && candidates+=("\$candidate")
  done

  if ((\${#candidates[@]} == 0)); then
    while IFS= read -r candidate; do
      [[ -n "\$candidate" ]] || continue
      [[ "\$candidate" == *"/kernel/"* ]] && continue
      candidates+=("\$candidate")
    done < <(find "/lib/modules/\$kernelver" -type f -name "\$basename" | LC_ALL=C sort)
  fi

  printf '%s\\n' "\${candidates[@]}" | awk '!seen[\$0]++'
}

sign_managed_dkms_module_install() {
  local module="\$1"
  local module_version="\$2"
  local kernelver="\$3"
  local arch="\$4"
  local base_dir=""
  local stored_module=""
  local basename=""
  local candidate=""
  local found=0

  base_dir="\$LABWC_DKMS_TREE/\$module/\$module_version/\$kernelver/\$arch/module"
  [[ -d "\$base_dir" ]] || return 0

  for stored_module in "\$base_dir"/*.ko*; do
    [[ -f "\$stored_module" ]] || continue
    basename="\${stored_module##*/}"
    while IFS= read -r candidate; do
      [[ -n "\$candidate" ]] || continue
      sign_module_in_place "\$candidate"
      found=1
    done < <(find_installed_dkms_candidates "\$kernelver" "\$basename")
  done

  if (( found == 0 )); then
    log_warn "no installed module artifacts were found for managed DKMS module \$module/\$module_version on kernel \$kernelver"
  fi
}

verify_managed_dkms_module_install() {
  local module="\$1"
  local module_version="\$2"
  local kernelver="\$3"
  local arch="\$4"
  local base_dir=""
  local stored_module=""
  local basename=""
  local candidate=""
  local found=0

  base_dir="\$LABWC_DKMS_TREE/\$module/\$module_version/\$kernelver/\$arch/module"
  [[ -d "\$base_dir" ]] || return 0

  for stored_module in "\$base_dir"/*.ko*; do
    [[ -f "\$stored_module" ]] || continue
    basename="\${stored_module##*/}"
    while IFS= read -r candidate; do
      [[ -n "\$candidate" ]] || continue
      module_is_labwc_signed "\$candidate" || die "managed DKMS module is not signed with the Labwc key: \$candidate"
      found=1
    done < <(find_installed_dkms_candidates "\$kernelver" "\$basename")
  done

  if (( found == 0 )); then
    log_warn "no installed module artifacts were found for managed DKMS module \$module/\$module_version on kernel \$kernelver"
  fi
}

list_dkms_status_records() {
  local line=""
  local module=""
  local module_version=""
  local kernelver=""
  local arch=""
  local state=""

  command -v dkms >/dev/null 2>&1 || return 0
  while IFS= read -r line; do
    [[ -n "\$line" ]] || continue
    if [[ "\$line" =~ ^([^/]+)/([^,]+),[[:space:]]*([^,]+),[[:space:]]*([^:]+):[[:space:]]*(.+)\$ ]]; then
      module="\${BASH_REMATCH[1]}"
      module_version="\${BASH_REMATCH[2]}"
      kernelver="\${BASH_REMATCH[3]}"
      arch="\${BASH_REMATCH[4]}"
      state="\${BASH_REMATCH[5]}"
      printf '%s|%s|%s|%s|%s\\n' "\$module" "\$module_version" "\$kernelver" "\$arch" "\$state"
    fi
  done < <(dkms status 2>/dev/null || true)
}

expand_module_glob_for_kernel() {
  local raw_pattern="\$1"
  local kernelver="\$2"
  local expanded_pattern=""
  local match=""
  local -a matches=()

  expanded_pattern="\${raw_pattern//\\\$kernelver/\$kernelver}"
  [[ "\$expanded_pattern" == /* ]] || die "expanded MODULE_GLOB must remain absolute: \$raw_pattern"
  matches=( \$expanded_pattern )
  for match in "\${matches[@]}"; do
    [[ -f "\$match" ]] || continue
    printf '%s\\n' "\$match"
  done
}

sign_non_dkms_for_kernel() {
  local kernelver="\$1"
  local pattern=""
  local module_path=""

  for pattern in "\${MODULE_GLOBS[@]}"; do
    while IFS= read -r module_path; do
      [[ -n "\$module_path" ]] || continue
      sign_module_in_place "\$module_path"
    done < <(expand_module_glob_for_kernel "\$pattern" "\$kernelver")
  done
}

verify_non_dkms_for_kernel() {
  local kernelver="\$1"
  local pattern=""
  local module_path=""

  for pattern in "\${MODULE_GLOBS[@]}"; do
    while IFS= read -r module_path; do
      [[ -n "\$module_path" ]] || continue
      module_is_labwc_signed "\$module_path" || die "managed non-DKMS module is not signed with the Labwc key: \$module_path"
    done < <(expand_module_glob_for_kernel "\$pattern" "\$kernelver")
  done
}

sign_managed_dkms_for_kernel() {
  local target_kernelver="\$1"
  local module=""
  local module_version=""
  local kernelver=""
  local arch=""
  local state=""

  while IFS='|' read -r module module_version kernelver arch state; do
    [[ "\$kernelver" == "\$target_kernelver" ]] || continue
    [[ "\$state" == installed* ]] || continue
    dkms_module_is_managed "\$module" "\$module_version" || continue
    sign_managed_dkms_module_install "\$module" "\$module_version" "\$kernelver" "\$arch"
  done < <(list_dkms_status_records)
}

verify_managed_dkms_for_kernel() {
  local target_kernelver="\$1"
  local module=""
  local module_version=""
  local kernelver=""
  local arch=""
  local state=""

  while IFS='|' read -r module module_version kernelver arch state; do
    [[ "\$kernelver" == "\$target_kernelver" ]] || continue
    [[ "\$state" == installed* ]] || continue
    dkms_module_is_managed "\$module" "\$module_version" || continue
    verify_managed_dkms_module_install "\$module" "\$module_version" "\$kernelver" "\$arch"
  done < <(list_dkms_status_records)
}

list_external_module_files_for_kernel() {
  local kernelver="\$1"
  local root=""

  for root in \
    "/lib/modules/\$kernelver/updates" \
    "/lib/modules/\$kernelver/extra"; do
    [[ -d "\$root" ]] || continue
    find "\$root" -type f \
      \( -name '*.ko' -o -name '*.ko.gz' -o -name '*.ko.xz' -o -name '*.ko.zst' \)
  done | LC_ALL=C sort -u
}

custom_module_build_dir_for_source() {
  local source_dir="\$1"
  local kernelver="\$2"
  local source_name=""
  local source_hash=""

  source_name="\$(basename -- "\$source_dir")"
  source_hash="\$(printf '%s' "\$source_dir" | sha256sum | awk '{print substr(\$1, 1, 12)}')"
  printf '%s/%s/%s-%s' "\$LABWC_CUSTOM_MODULE_BUILD_ROOT" "\$kernelver" "\$source_name" "\$source_hash"
}

list_custom_module_source_dirs() {
  local source_dir=""

  [[ -d "\$LABWC_CUSTOM_MODULE_SOURCE_ROOT" ]] || return 0
  while IFS= read -r source_dir; do
    [[ -f "\$source_dir/Makefile" || -f "\$source_dir/Kbuild" ]] || continue
    printf '%s\\n' "\$source_dir"
  done < <(find "\$LABWC_CUSTOM_MODULE_SOURCE_ROOT" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)
}

build_custom_module_source_dir() {
  local source_dir="\$1"
  local kernelver="\$2"
  local kernel_build_dir=""
  local build_dir=""

  kernel_build_dir="/lib/modules/\$kernelver/build"
  if [[ ! -d "\$kernel_build_dir" ]]; then
    log_warn "skipping custom module tree \$source_dir because \$kernel_build_dir is not present"
    return 0
  fi

  build_dir="\$(custom_module_build_dir_for_source "\$source_dir" "\$kernelver")"
  rm -rf -- "\$build_dir"
  mkdir -p "\$build_dir"

  log_info "building custom external module tree \$source_dir for kernel \$kernelver"
  make -C "\$kernel_build_dir" M="\$source_dir" MO="\$build_dir" modules

  log_info "installing custom external module tree \$source_dir into /lib/modules/\$kernelver/extra"
  make -C "\$kernel_build_dir" M="\$source_dir" MO="\$build_dir" INSTALL_MOD_DIR=extra modules_install
  mark_kernel_for_depmod "\$kernelver"
}

build_custom_modules_for_kernel() {
  local kernelver="\$1"
  local source_dir=""

  while IFS= read -r source_dir; do
    [[ -n "\$source_dir" ]] || continue
    build_custom_module_source_dir "\$source_dir" "\$kernelver"
  done < <(list_custom_module_source_dirs)
}

all_installed_kernel_versions() {
  local module_dir=""

  for module_dir in /lib/modules/*; do
    [[ -d "\$module_dir" ]] || continue
    printf '%s\\n' "\${module_dir##*/}"
  done | LC_ALL=C sort -u
}

cmd_sign() {
  local module_path=""

  (( \$# >= 1 )) || die "usage: sign-module <module-path> [module-path ...]"
  load_modules_config
  verify_managed_keypair
  for module_path in "\$@"; do
    sign_module_in_place "\$module_path"
  done
  run_depmod_for_changed_kernels
}

cmd_kernel_hook() {
  local pkg_type="\$1"
  local kernelver="\$2"

  [[ "\$pkg_type" == image || "\$pkg_type" == headers || "\$pkg_type" == manual ]] || die "unsupported kernel-hook package type: \$pkg_type"
  [[ -n "\$kernelver" ]] || die "kernel-hook requires a kernel version"
  load_modules_config
  verify_managed_keypair
  sync_dkms_overrides apply
  if [[ "\$pkg_type" == headers || "\$pkg_type" == manual ]]; then
    build_custom_modules_for_kernel "\$kernelver"
  fi
  while IFS= read -r module_path; do
    [[ -n "\$module_path" ]] || continue
    sign_module_in_place "\$module_path"
  done < <(list_external_module_files_for_kernel "\$kernelver")
  sign_managed_dkms_for_kernel "\$kernelver"
  sign_non_dkms_for_kernel "\$kernelver"
  run_depmod_for_changed_kernels
}

cmd_dkms_post_install() {
  local module="\${1:-}"
  local module_version="\${2:-}"
  local kernelver="\${3:-}"
  local arch="\${4:-}"

  [[ -n "\$module" && -n "\$module_version" && -n "\$kernelver" && -n "\$arch" ]] || {
    die "dkms-post-install requires module, module_version, kernelver, and arch"
  }
  load_modules_config
  verify_managed_keypair
  dkms_module_is_managed "\$module" "\$module_version" || exit 0
  sign_managed_dkms_module_install "\$module" "\$module_version" "\$kernelver" "\$arch"
  run_depmod_for_changed_kernels
}

cmd_refresh_dkms_overrides() {
  load_modules_config
  sync_dkms_overrides apply
}

cmd_repair_installed_modules() {
  local kernelver=""

  load_modules_config
  verify_managed_keypair
  sync_dkms_overrides apply
  while IFS= read -r kernelver; do
    [[ -n "\$kernelver" ]] || continue
    build_custom_modules_for_kernel "\$kernelver"
    while IFS= read -r module_path; do
      [[ -n "\$module_path" ]] || continue
      sign_module_in_place "\$module_path"
    done < <(list_external_module_files_for_kernel "\$kernelver")
    sign_managed_dkms_for_kernel "\$kernelver"
    sign_non_dkms_for_kernel "\$kernelver"
  done < <(all_installed_kernel_versions)
  run_depmod_for_changed_kernels
}

cmd_verify_dkms_overrides() {
  load_modules_config
  sync_dkms_overrides check
}

cmd_verify_managed_modules() {
  local kernelver=""

  load_modules_config
  verify_managed_keypair
  while IFS= read -r kernelver; do
    [[ -n "\$kernelver" ]] || continue
    while IFS= read -r module_path; do
      [[ -n "\$module_path" ]] || continue
      module_is_labwc_signed "\$module_path" || die "out-of-tree module under updates/extra is not signed with the Labwc key: \$module_path"
    done < <(list_external_module_files_for_kernel "\$kernelver")
    verify_managed_dkms_for_kernel "\$kernelver"
    verify_non_dkms_for_kernel "\$kernelver"
  done < <(all_installed_kernel_versions)
}

cmd_validate_config() {
  load_modules_config
}

main() {
  local command="\${1:-}"
  shift || true

  require_command awk
  require_command chown
  require_command chmod
  require_command cp
  require_command dpkg-query
  require_command find
  require_command gzip
  require_command install
  require_command make
  require_command mv
  require_command openssl
  require_command readlink
  require_command rm
  require_command sha256sum
  require_command stat
  require_command touch
  require_command xz
  require_command zstd
  command -v dkms >/dev/null 2>&1 || true

  case "\$command" in
    sign) cmd_sign "\$@" ;;
    kernel-hook) cmd_kernel_hook "\$@" ;;
    dkms-post-install) cmd_dkms_post_install "\$@" ;;
    refresh-dkms-overrides) cmd_refresh_dkms_overrides "\$@" ;;
    repair-installed-modules) cmd_repair_installed_modules "\$@" ;;
    verify-dkms-overrides) cmd_verify_dkms_overrides "\$@" ;;
    verify-managed-modules) cmd_verify_managed_modules "\$@" ;;
    validate-config) cmd_validate_config "\$@" ;;
    *)
      die "unsupported command: \${command:-<empty>}"
      ;;
  esac
}

main "\$@"
EOF
}

build_sign_module_helper_candidate() {
  local destination_path="$1"

  cat >"$destination_path" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=\$'\\n\\t'
exec "${SYSTEM_SECURE_BOOT_TOOL_PATH}" sign "\$@"
EOF
}

build_kernel_postinst_hook_candidate() {
  local destination_path="$1"

  cat >"$destination_path" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=\$'\\n\\t'
exec "${SYSTEM_SECURE_BOOT_TOOL_PATH}" kernel-hook image "\$@"
EOF
}

build_kernel_header_postinst_hook_candidate() {
  local destination_path="$1"

  cat >"$destination_path" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=\$'\\n\\t'
exec "${SYSTEM_SECURE_BOOT_TOOL_PATH}" kernel-hook headers "\$@"
EOF
}

build_managed_dkms_candidate() {
  local destination_path="$1"

  cat >"$destination_path" <<EOF
# Managed locally. Do not edit manually.
mok_signing_key="${SYSTEM_SECURE_BOOT_KEY_PATH}"
mok_certificate="${SYSTEM_SECURE_BOOT_CERT_PATH}"
sign_file="/lib/modules/\${kernelver}/build/scripts/sign-file"
EOF
}

certificate_fingerprint() {
  local certificate_path="$1"
  local format="${2:-DER}"
  local fingerprint=""

  fingerprint="$(
    openssl x509 \
      -inform "$format" \
      -in "$certificate_path" \
      -noout \
      -fingerprint \
      -sha1 2>/dev/null
  )" || return 1

  printf '%s' "${fingerprint##*=}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]:'
}

certificate_subject_rfc2253() {
  local certificate_path="$1"
  local format="${2:-DER}"

  openssl x509 \
    -inform "$format" \
    -in "$certificate_path" \
    -noout \
    -subject \
    -nameopt RFC2253 2>/dev/null | sed 's/^subject=//'
}

certificate_subject_has_managed_cn() {
  local certificate_path="$1"
  local format="${2:-DER}"
  local subject=""

  subject="$(certificate_subject_rfc2253 "$certificate_path" "$format")" || return 1
  subject_has_managed_cn "$subject"
}

subject_contains_expected_labwc_identity() {
  local subject="$1"

  [[ "$subject" == *"C=${SYSTEM_SECURE_BOOT_COUNTRY}"* ]] || return 1
  [[ "$subject" == *"ST=${SYSTEM_SECURE_BOOT_STATE}"* ]] || return 1
  [[ "$subject" == *"L=${SYSTEM_SECURE_BOOT_LOCALITY}"* ]] || return 1
  [[ "$subject" == *"O=${SYSTEM_SECURE_BOOT_ORGANIZATION}"* ]] || return 1
  [[ "$subject" == *"OU=${SYSTEM_SECURE_BOOT_ORG_UNIT}"* ]] || return 1
  [[ "$subject" == *"CN=${SYSTEM_SECURE_BOOT_CN}"* ]] || return 1
  [[ "$subject" == *"emailAddress=${SYSTEM_SECURE_BOOT_EMAIL}"* ]] || return 1
}

certificate_subject_is_managed_labwc() {
  local certificate_path="$1"
  local format="${2:-DER}"
  local subject=""

  subject="$(certificate_subject_rfc2253 "$certificate_path" "$format")" || return 1
  subject_contains_expected_labwc_identity "$subject"
}

managed_secure_boot_material_complete() {
  [[ -f "$SYSTEM_SECURE_BOOT_KEY_PATH" && -f "$SYSTEM_SECURE_BOOT_CERT_PATH" && -f "$SYSTEM_SECURE_BOOT_OPENSSL_CONFIG_PATH" ]]
}

managed_secure_boot_material_partial() {
  [[ -e "$SYSTEM_SECURE_BOOT_KEY_PATH" || -e "$SYSTEM_SECURE_BOOT_CERT_PATH" || -e "$SYSTEM_SECURE_BOOT_OPENSSL_CONFIG_PATH" ]]
}

managed_secure_boot_material_valid() {
  local key_public=""
  local cert_public=""

  managed_secure_boot_material_complete || return 1
  certificate_subject_is_managed_labwc "$SYSTEM_SECURE_BOOT_CERT_PATH" DER || return 1

  openssl pkey -in "$SYSTEM_SECURE_BOOT_KEY_PATH" -passin pass: -noout >/dev/null 2>&1 || return 1
  key_public="$(
    openssl pkey \
      -in "$SYSTEM_SECURE_BOOT_KEY_PATH" \
      -passin pass: \
      -pubout \
      -outform PEM 2>/dev/null
  )" || return 1
  cert_public="$(
    openssl x509 \
      -inform DER \
      -in "$SYSTEM_SECURE_BOOT_CERT_PATH" \
      -pubkey \
      -noout 2>/dev/null
  )" || return 1
  [[ "$key_public" == "$cert_public" ]]
}

ensure_secure_boot_directory_layout() {
  ensure_directory_state "$SYSTEM_SECURE_BOOT_DIR" root root "$SYSTEM_SECURE_BOOT_DIR_MODE"
  run_cmd install -d -m 0755 -o root -g root "$SYSTEM_SECURE_BOOT_CONFIG_DIR"
  run_cmd install -d -m 0755 -o root -g root "$SYSTEM_SECURE_BOOT_TOOL_DIR"
  run_cmd install -d -m 0755 -o root -g root "$SYSTEM_CUSTOM_MODULE_SOURCE_ROOT"
  run_cmd install -d -m 0755 -o root -g root "$SYSTEM_CUSTOM_MODULE_BUILD_ROOT"
  run_cmd install -d -m 0755 -o root -g root "$SYSTEM_DKMS_CONF_DIR"
  run_cmd install -d -m 0755 -o root -g root "$SYSTEM_KERNEL_HEADER_POSTINST_HOOK_DIR"
}

write_managed_secure_boot_openssl_config() {
  local config_content=""

  ensure_secure_boot_directory_layout
  config_content="$(render_managed_secure_boot_openssl_config)"
  run_cmd install -m "$SYSTEM_SECURE_BOOT_FILE_MODE" -o root -g root /dev/null "$SYSTEM_SECURE_BOOT_OPENSSL_CONFIG_PATH"
  printf '%s\n' "$config_content" >"$SYSTEM_SECURE_BOOT_OPENSSL_CONFIG_PATH"
  run_cmd chown root:root "$SYSTEM_SECURE_BOOT_OPENSSL_CONFIG_PATH"
  run_cmd chmod "$SYSTEM_SECURE_BOOT_FILE_MODE" "$SYSTEM_SECURE_BOOT_OPENSSL_CONFIG_PATH"
}

remove_managed_secure_boot_local_state() {
  if [[ -d "$SYSTEM_SECURE_BOOT_DIR" ]]; then
    run_cmd rm -rf -- "$SYSTEM_SECURE_BOOT_DIR"
  fi
}

install_template_if_missing() {
  local source_path="$1"
  local destination_path="$2"
  local mode="$3"

  if [[ -f "$destination_path" ]]; then
    return 0
  fi

  run_cmd install -m "$mode" -o root -g root "$source_path" "$destination_path"
}

install_script_candidate() {
  local candidate_builder="$1"
  local destination_path="$2"
  local mode="$3"
  local candidate_path=""

  candidate_path="$(mktemp)"
  "$candidate_builder" "$candidate_path"
  if [[ -f "$destination_path" ]] && cmp -s "$candidate_path" "$destination_path"; then
    rm -f -- "$candidate_path"
    return 0
  fi

  run_cmd install -m "$mode" -o root -g root "$candidate_path" "$destination_path"
  rm -f -- "$candidate_path"
}

apply_managed_dkms_signing_config() {
  local candidate_path=""

  ensure_secure_boot_directory_layout
  candidate_path="$(mktemp)"
  build_managed_dkms_candidate "$candidate_path"

  if [[ -f "$SYSTEM_DKMS_CONF_PATH" ]] && cmp -s "$candidate_path" "$SYSTEM_DKMS_CONF_PATH"; then
    rm -f -- "$candidate_path"
    return 0
  fi

  run_cmd install -m "$SYSTEM_DKMS_CONF_MODE" -o root -g root "$candidate_path" "$SYSTEM_DKMS_CONF_PATH"
  rm -f -- "$candidate_path"
}

generate_managed_secure_boot_material() {
  local certificate_pem_path=""

  log_info "generating managed Secure Boot key material in $SYSTEM_SECURE_BOOT_DIR"
  ensure_secure_boot_directory_layout
  write_managed_secure_boot_openssl_config
  certificate_pem_path="$(mktemp "${SYSTEM_SECURE_BOOT_DIR}/MOK.pem.XXXXXX")"
  run_cmd rm -f -- "$SYSTEM_SECURE_BOOT_KEY_PATH" "$SYSTEM_SECURE_BOOT_CERT_PATH"
  run_cmd openssl req \
    -new \
    -x509 \
    -batch \
    -noenc \
    -sha256 \
    -days "$SYSTEM_SECURE_BOOT_VALID_DAYS" \
    -newkey "rsa:${SYSTEM_SECURE_BOOT_KEY_BITS}" \
    -config "$SYSTEM_SECURE_BOOT_OPENSSL_CONFIG_PATH" \
    -keyout "$SYSTEM_SECURE_BOOT_KEY_PATH" \
    -out "$certificate_pem_path"
  run_cmd openssl x509 \
    -in "$certificate_pem_path" \
    -outform DER \
    -out "$SYSTEM_SECURE_BOOT_CERT_PATH"
  run_cmd rm -f -- "$certificate_pem_path"
  run_cmd chown root:root "$SYSTEM_SECURE_BOOT_KEY_PATH" "$SYSTEM_SECURE_BOOT_CERT_PATH"
  run_cmd chmod "$SYSTEM_SECURE_BOOT_FILE_MODE" "$SYSTEM_SECURE_BOOT_KEY_PATH" "$SYSTEM_SECURE_BOOT_CERT_PATH"
  managed_secure_boot_material_valid || die "generated Secure Boot key material is invalid"
}

mok_pending_stream() {
  local mode="$1"

  case "$mode" in
    import)
      mokutil --list-new 2>/dev/null
      ;;
    delete)
      mokutil --list-delete 2>/dev/null
      ;;
    *)
      die "unsupported pending MOK mode: $mode"
      ;;
  esac
}

mok_pending_entries() {
  local mode="$1"
  local line=""
  local fingerprint=""
  local subject=""

  while IFS= read -r line; do
    if [[ "$line" =~ ^\[key[[:space:]][0-9]+\]$ ]]; then
      if [[ -n "$fingerprint" || -n "$subject" ]]; then
        printf '%s|%s\n' "$fingerprint" "$subject"
      fi
      fingerprint=""
      subject=""
      continue
    fi

    if [[ "$line" =~ ^SHA1[[:space:]]Fingerprint:[[:space:]](.+)$ ]]; then
      fingerprint="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]:')"
      continue
    fi

    if [[ "$line" =~ ^[[:space:]]*Subject:[[:space:]]*(.+)$ ]]; then
      subject="${BASH_REMATCH[1]}"
      continue
    fi
  done < <(mok_pending_stream "$mode")

  if [[ -n "$fingerprint" || -n "$subject" ]]; then
    printf '%s|%s\n' "$fingerprint" "$subject"
  fi
}

subject_has_managed_cn() {
  local subject_line="$1"

  grep -Eq '(^|[,[:space:]])CN[[:space:]]*=[[:space:]]*Labwc Secure Boot($|[,[:space:]])' <<<"$subject_line"
}

managed_pending_mok_fingerprints() {
  local mode="$1"
  local fingerprint=""
  local subject=""

  while IFS='|' read -r fingerprint subject; do
    [[ -n "$fingerprint" ]] || continue
    subject_has_managed_cn "$subject" || continue
    printf '%s\n' "$fingerprint"
  done < <(mok_pending_entries "$mode")
}

pending_mok_has_unmanaged_entries() {
  local mode="$1"
  local fingerprint=""
  local subject=""

  while IFS='|' read -r fingerprint subject; do
    [[ -n "$fingerprint" || -n "$subject" ]] || continue
    subject_has_managed_cn "$subject" && continue
    return 0
  done < <(mok_pending_entries "$mode")

  return 1
}

load_sorted_fingerprints() {
  local -n target_ref="$1"
  shift

  mapfile -t target_ref < <("$@" | LC_ALL=C sort -u)
}

fingerprint_arrays_equal() {
  local -n left_ref="$1"
  local -n right_ref="$2"
  local index

  ((${#left_ref[@]} == ${#right_ref[@]})) || return 1
  for index in "${!left_ref[@]}"; do
    [[ "${left_ref[$index]}" == "${right_ref[$index]}" ]] || return 1
  done
}

managed_enrolled_fingerprints() {
  local temp_dir=""
  local certificate_path=""
  local fingerprint=""

  temp_dir="$(mktemp -d)"
  (
    cd "$temp_dir"
    mokutil --export >/dev/null
  )

  for certificate_path in "$temp_dir"/MOK-*.der; do
    [[ -f "$certificate_path" ]] || continue
    if ! certificate_subject_has_managed_cn "$certificate_path" DER; then
      continue
    fi
    fingerprint="$(certificate_fingerprint "$certificate_path" DER)" || {
      rm -rf -- "$temp_dir"
      die "could not fingerprint exported certificate $certificate_path"
    }
    printf '%s\n' "$fingerprint"
  done

  rm -rf -- "$temp_dir"
}

queue_managed_mok_deletions() {
  local preserve_fingerprint="$1"
  local temp_dir=""
  local certificate_path=""
  local fingerprint=""
  local -a delete_candidates=()

  temp_dir="$(mktemp -d)"
  (
    cd "$temp_dir"
    mokutil --export >/dev/null
  )

  for certificate_path in "$temp_dir"/MOK-*.der; do
    [[ -f "$certificate_path" ]] || continue
    if ! certificate_subject_has_managed_cn "$certificate_path" DER; then
      continue
    fi
    fingerprint="$(certificate_fingerprint "$certificate_path" DER)" || {
      rm -rf -- "$temp_dir"
      die "could not fingerprint exported certificate $certificate_path"
    }
    if [[ -n "$preserve_fingerprint" && "$fingerprint" == "$preserve_fingerprint" ]]; then
      continue
    fi
    delete_candidates+=("$certificate_path")
  done

  if ((${#delete_candidates[@]} > 0)); then
    log_warn "queueing MOK deletion for ${#delete_candidates[@]} enrolled certificate(s) with CN=${SYSTEM_SECURE_BOOT_CN}; mokutil will prompt for a password"
    run_cmd mokutil --delete "${delete_candidates[@]}"
  fi

  rm -rf -- "$temp_dir"
}

current_managed_cert_enrolled() {
  mokutil --test-key "$SYSTEM_SECURE_BOOT_CERT_PATH" >/dev/null 2>&1
}

revoke_managed_pending_imports() {
  pending_mok_has_unmanaged_entries import && {
    die "cannot revoke pending Labwc MOK imports while unrelated pending MOK imports exist"
  }
  log_warn "clearing stale pending Labwc MOK import requests"
  run_cmd mokutil --revoke-import
}

revoke_managed_pending_deletes() {
  pending_mok_has_unmanaged_entries delete && {
    die "cannot revoke pending Labwc MOK deletions while unrelated pending MOK delete requests exist"
  }
  log_warn "clearing stale pending Labwc MOK delete requests"
  run_cmd mokutil --revoke-delete
}

apply_secure_boot_tooling() {
  ensure_secure_boot_directory_layout
  install_template_if_missing \
    "$SYSTEM_SECURE_BOOT_MODULES_TEMPLATE_PATH" \
    "$SYSTEM_SECURE_BOOT_MODULES_CONFIG_PATH" \
    "$SYSTEM_SECURE_BOOT_CONFIG_MODE"
  install_script_candidate build_secure_boot_tool_candidate "$SYSTEM_SECURE_BOOT_TOOL_PATH" "$SYSTEM_SECURE_BOOT_TOOL_MODE"
  install_script_candidate build_sign_module_helper_candidate "$SYSTEM_SIGN_MODULE_HELPER" "$SYSTEM_SIGN_MODULE_HELPER_MODE"
  install_script_candidate build_kernel_postinst_hook_candidate "$SYSTEM_KERNEL_POSTINST_HOOK_PATH" "$SYSTEM_KERNEL_HOOK_MODE"
  install_script_candidate build_kernel_header_postinst_hook_candidate "$SYSTEM_KERNEL_HEADER_POSTINST_HOOK_PATH" "$SYSTEM_KERNEL_HOOK_MODE"
  run_cmd "$SYSTEM_SECURE_BOOT_TOOL_PATH" validate-config
  run_cmd "$SYSTEM_SECURE_BOOT_TOOL_PATH" refresh-dkms-overrides
}

managed_secure_boot_file_state() {
  stat -c '%U:%G:%a' "$1"
}

verify_managed_secure_boot_permissions() {
  local path=""

  assert_directory_state "$SYSTEM_SECURE_BOOT_DIR" root root "$SYSTEM_SECURE_BOOT_DIR_MODE"

  for path in \
    "$SYSTEM_DKMS_CONF_PATH" \
    "$SYSTEM_SECURE_BOOT_KEY_PATH" \
    "$SYSTEM_SECURE_BOOT_CERT_PATH" \
    "$SYSTEM_SECURE_BOOT_OPENSSL_CONFIG_PATH"; do
    require_file "$path"
    [[ "$(managed_secure_boot_file_state "$path")" == "root:root:${SYSTEM_SECURE_BOOT_FILE_MODE#0}" ]] || {
      die "unexpected file state for $path: $(managed_secure_boot_file_state "$path")"
    }
  done

  require_file "$SYSTEM_SECURE_BOOT_MODULES_CONFIG_PATH"
  [[ "$(managed_secure_boot_file_state "$SYSTEM_SECURE_BOOT_MODULES_CONFIG_PATH")" == "root:root:${SYSTEM_SECURE_BOOT_CONFIG_MODE#0}" ]] || {
    die "unexpected file state for $SYSTEM_SECURE_BOOT_MODULES_CONFIG_PATH: $(managed_secure_boot_file_state "$SYSTEM_SECURE_BOOT_MODULES_CONFIG_PATH")"
  }
  [[ "$(managed_secure_boot_file_state "$SYSTEM_CUSTOM_MODULE_SOURCE_ROOT")" == "root:root:755" ]] || {
    die "unexpected source root state for $SYSTEM_CUSTOM_MODULE_SOURCE_ROOT: $(managed_secure_boot_file_state "$SYSTEM_CUSTOM_MODULE_SOURCE_ROOT")"
  }
  [[ "$(managed_secure_boot_file_state "$SYSTEM_CUSTOM_MODULE_BUILD_ROOT")" == "root:root:755" ]] || {
    die "unexpected build root state for $SYSTEM_CUSTOM_MODULE_BUILD_ROOT: $(managed_secure_boot_file_state "$SYSTEM_CUSTOM_MODULE_BUILD_ROOT")"
  }

  for path in \
    "$SYSTEM_SECURE_BOOT_TOOL_PATH" \
    "$SYSTEM_SIGN_MODULE_HELPER" \
    "$SYSTEM_KERNEL_POSTINST_HOOK_PATH" \
    "$SYSTEM_KERNEL_HEADER_POSTINST_HOOK_PATH"; do
    require_file "$path"
    [[ "$(managed_secure_boot_file_state "$path")" == "root:root:755" ]] || {
      die "unexpected helper state for $path: $(managed_secure_boot_file_state "$path")"
    }
  done

  [[ "$(managed_secure_boot_file_state "$SYSTEM_DKMS_CONF_PATH")" == "root:root:${SYSTEM_DKMS_CONF_MODE#0}" ]] || {
    die "unexpected DKMS config state for $SYSTEM_DKMS_CONF_PATH: $(managed_secure_boot_file_state "$SYSTEM_DKMS_CONF_PATH")"
  }
}

verify_managed_dkms_signing_config() {
  local candidate_path=""

  candidate_path="$(mktemp)"
  build_managed_dkms_candidate "$candidate_path"
  cmp -s "$candidate_path" "$SYSTEM_DKMS_CONF_PATH" || {
    rm -f -- "$candidate_path"
    die "$SYSTEM_DKMS_CONF_PATH does not match the generated DKMS signing configuration"
  }
  rm -f -- "$candidate_path"
}

verify_managed_secure_boot_material() {
  managed_secure_boot_material_valid || die "managed Secure Boot key material is missing, malformed, encrypted, or does not match the expected Labwc identity"
}

verify_managed_secure_boot() {
  local current_fingerprint=""
  local -a pending_imports=()
  local -a pending_deletes=()
  local -a enrolled_managed=()
  local -a desired_imports=()
  local -a desired_deletes=()
  local fingerprint=""

  require_secure_boot_runtime
  verify_managed_secure_boot_permissions
  verify_managed_secure_boot_material
  verify_managed_dkms_signing_config
  run_cmd "$SYSTEM_SECURE_BOOT_TOOL_PATH" validate-config
  run_cmd "$SYSTEM_SECURE_BOOT_TOOL_PATH" verify-dkms-overrides
  run_cmd "$SYSTEM_SECURE_BOOT_TOOL_PATH" verify-managed-modules

  current_fingerprint="$(certificate_fingerprint "$SYSTEM_SECURE_BOOT_CERT_PATH" DER)" || {
    die "could not fingerprint $SYSTEM_SECURE_BOOT_CERT_PATH"
  }

  load_sorted_fingerprints pending_imports managed_pending_mok_fingerprints import
  load_sorted_fingerprints pending_deletes managed_pending_mok_fingerprints delete
  load_sorted_fingerprints enrolled_managed managed_enrolled_fingerprints

  if ! current_managed_cert_enrolled; then
    desired_imports=("$current_fingerprint")
  fi

  for fingerprint in "${enrolled_managed[@]}"; do
    if [[ "$fingerprint" != "$current_fingerprint" ]]; then
      desired_deletes+=("$fingerprint")
    fi
  done

  if ! fingerprint_arrays_equal pending_imports desired_imports; then
    die "pending Labwc MOK imports do not match the managed certificate state"
  fi

  if ! fingerprint_arrays_equal pending_deletes desired_deletes; then
    die "pending Labwc MOK deletions do not match the managed enrolled-certificate state"
  fi
}

apply_managed_secure_boot() {
  local current_fingerprint=""
  local current_enrolled=0
  local regenerated=0
  local fingerprint=""
  local -a pending_imports=()
  local -a pending_deletes=()
  local -a desired_imports=()
  local -a desired_deletes=()
  local -a enrolled_managed=()

  ensure_secure_boot_packages
  require_secure_boot_runtime
  log_secure_boot_state
  ensure_secure_boot_directory_layout

  if managed_secure_boot_material_partial && ! managed_secure_boot_material_valid; then
    log_warn "managed Secure Boot key material is incomplete or invalid; resetting the dedicated Labwc key directory"
    revoke_managed_pending_imports || true
    revoke_managed_pending_deletes || true
    remove_managed_secure_boot_local_state
  fi

  if ! managed_secure_boot_material_valid; then
    generate_managed_secure_boot_material
    regenerated=1
  fi

  current_fingerprint="$(certificate_fingerprint "$SYSTEM_SECURE_BOOT_CERT_PATH" DER)" || {
    die "could not fingerprint $SYSTEM_SECURE_BOOT_CERT_PATH"
  }

  load_sorted_fingerprints pending_imports managed_pending_mok_fingerprints import
  load_sorted_fingerprints pending_deletes managed_pending_mok_fingerprints delete
  load_sorted_fingerprints enrolled_managed managed_enrolled_fingerprints

  if current_managed_cert_enrolled; then
    current_enrolled=1
  fi

  if (( current_enrolled == 0 )); then
    desired_imports=("$current_fingerprint")
  fi

  for fingerprint in "${enrolled_managed[@]}"; do
    if [[ "$fingerprint" != "$current_fingerprint" ]]; then
      desired_deletes+=("$fingerprint")
    fi
  done

  if ! fingerprint_arrays_equal pending_deletes desired_deletes; then
    if ((${#pending_deletes[@]} > 0)); then
      revoke_managed_pending_deletes
    fi
    if ((${#desired_deletes[@]} > 0)); then
      queue_managed_mok_deletions "$current_fingerprint"
      load_sorted_fingerprints pending_deletes managed_pending_mok_fingerprints delete
      fingerprint_arrays_equal pending_deletes desired_deletes || {
        die "failed to queue the expected Labwc MOK delete requests"
      }
    fi
  fi

  if ! fingerprint_arrays_equal pending_imports desired_imports; then
    if ((${#pending_imports[@]} > 0)); then
      revoke_managed_pending_imports
    fi
    if ((${#desired_imports[@]} > 0)); then
      log_warn "queueing MOK import for ${SYSTEM_SECURE_BOOT_CERT_PATH}; mokutil will prompt for a password"
      run_cmd mokutil --import "$SYSTEM_SECURE_BOOT_CERT_PATH"
      load_sorted_fingerprints pending_imports managed_pending_mok_fingerprints import
      fingerprint_arrays_equal pending_imports desired_imports || {
        die "failed to queue the expected Labwc MOK import request"
      }
    fi
  fi

  apply_managed_dkms_signing_config
  apply_secure_boot_tooling
  if (( regenerated == 1 )); then
    log_info "managed Labwc key was regenerated; re-signing currently installed managed modules"
  fi
  run_cmd "$SYSTEM_SECURE_BOOT_TOOL_PATH" repair-installed-modules

  verify_managed_secure_boot

  if ((${#desired_imports[@]} > 0 || ${#desired_deletes[@]} > 0)); then
    log_warn "Secure Boot MOK changes are pending. Reboot and complete MokManager enrollment/deletion before relying on the new trust state."
  else
    log_info "Labwc Secure Boot key material, scoped hooks, and managed module signing state are aligned"
  fi
}

remove_managed_secure_boot() {
  local -a pending_imports=()
  local -a pending_deletes=()
  local -a enrolled_managed=()
  local conf_path=""
  local module_dir=""

  if command -v mokutil >/dev/null 2>&1 && command -v openssl >/dev/null 2>&1; then
    require_secure_boot_runtime
    load_sorted_fingerprints pending_imports managed_pending_mok_fingerprints import
    load_sorted_fingerprints pending_deletes managed_pending_mok_fingerprints delete
    load_sorted_fingerprints enrolled_managed managed_enrolled_fingerprints

    if ((${#pending_imports[@]} > 0)); then
      revoke_managed_pending_imports
    fi
    if ((${#pending_deletes[@]} > 0)); then
      revoke_managed_pending_deletes
    fi
    if ((${#enrolled_managed[@]} > 0)); then
      queue_managed_mok_deletions ""
      log_warn "Labwc Secure Boot certificate deletion is pending. Reboot and complete MokManager deletion to finish removal."
    fi
  else
    log_warn "mokutil/openssl are unavailable; removing only local Labwc Secure Boot files and hooks"
  fi

  for conf_path in /etc/dkms/*.conf; do
    [[ -f "$conf_path" ]] || continue
    grep -F "POST_INSTALL=\"labwc-secure-boot-dkms-post-install" "$conf_path" >/dev/null 2>&1 || continue
    run_cmd rm -f -- "$conf_path"
  done
  for module_dir in /etc/dkms/*; do
    [[ -d "$module_dir" ]] || continue
    if [[ -f "$module_dir/labwc-secure-boot-dkms-post-install" ]]; then
      run_cmd rm -f -- "$module_dir/labwc-secure-boot-dkms-post-install"
      if [[ -z "$(find "$module_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        run_cmd rmdir -- "$module_dir"
      fi
    fi
  done

  if [[ -f "$SYSTEM_DKMS_CONF_PATH" ]]; then
    run_cmd rm -f -- "$SYSTEM_DKMS_CONF_PATH"
  fi
  run_cmd rm -f -- \
    "$SYSTEM_SECURE_BOOT_TOOL_PATH" \
    "$SYSTEM_SIGN_MODULE_HELPER" \
    "$SYSTEM_KERNEL_POSTINST_HOOK_PATH" \
    "$SYSTEM_KERNEL_HEADER_POSTINST_HOOK_PATH"
  if [[ -d "$SYSTEM_SECURE_BOOT_TOOL_DIR" ]] && [[ -z "$(find "$SYSTEM_SECURE_BOOT_TOOL_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    run_cmd rmdir -- "$SYSTEM_SECURE_BOOT_TOOL_DIR"
  fi
  run_cmd rm -f -- "$SYSTEM_SECURE_BOOT_MODULES_CONFIG_PATH"
  if [[ -d "$SYSTEM_SECURE_BOOT_CONFIG_DIR" ]] && [[ -z "$(find "$SYSTEM_SECURE_BOOT_CONFIG_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    run_cmd rmdir -- "$SYSTEM_SECURE_BOOT_CONFIG_DIR"
  fi
  if [[ -d "$SYSTEM_CUSTOM_MODULE_BUILD_ROOT" ]]; then
    run_cmd rm -rf -- "$SYSTEM_CUSTOM_MODULE_BUILD_ROOT"
  fi
  remove_managed_secure_boot_local_state
}
