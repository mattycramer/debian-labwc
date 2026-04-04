SHELL := /usr/bin/env bash

.PHONY: help guard-non-root doctor sid mounts permissions secureboot sudoers install verify print-env nuke

help:
	@printf '%s\n' \
	  '00-system targets:' \
	  '  NOTE:        Run make as a non-root user; do not use sudo make' \
	  '  help         Show this message' \
	  '  doctor       Validate platform assumptions and resolve the invoking user' \
	  '  sid          Install /etc/apt/sources.list.d/sid.sources and /etc/apt/preferences.d/sid exactly as managed by 00-system' \
	  '  mounts       Install four device-gated top-level g-drive mount/watch units from mounts.conf' \
	  '  permissions  Create the hardened torrent account, add the invoking user to torrent, and repair required path ownership/modes including invoke-user write access on /pool/builds and /pool/cache' \
	  '  secureboot   Install Secure Boot dependencies, manage the Labwc MOK, install the DKMS framework drop-in, zz- kernel hooks, the custom module source root, and the sign-module helper' \
	  '  sudoers      Install the hardened invoking-user policy and read-only helper wrappers under /etc/sudoers.d' \
	  '  install      Run doctor, sid, permissions, mounts, secureboot, sudoers, and verify' \
	  '  verify       Check the managed sid archive files, generated mount units, Secure Boot state, sudoers, required path permissions, and invoke-user write access on /pool/builds and /pool/cache' \
	  '  print-env    Print resolved target user/path state' \
	  '  nuke         Remove generated Secure Boot state, scoped module hooks/helpers, mount units, and sudoers policy; directory permissions stay in place'

guard-non-root:
	@if [ "$$(id -u)" -eq 0 ]; then \
	  printf '%s\n' "Refusing to run 00-system from a root make process. Run 'make <target>' as a non-root user; do not use sudo make." >&2; \
	  exit 1; \
	fi

doctor: guard-non-root
	@SYSTEM_MAKE_WRAPPER=1 sudo --preserve-env=SYSTEM_MAKE_WRAPPER bash ./install.sh --phase doctor

sid: guard-non-root
	@SYSTEM_MAKE_WRAPPER=1 sudo --preserve-env=SYSTEM_MAKE_WRAPPER bash ./install.sh --phase sid

mounts: guard-non-root
	@SYSTEM_MAKE_WRAPPER=1 sudo --preserve-env=SYSTEM_MAKE_WRAPPER bash ./install.sh --phase mounts

permissions: guard-non-root
	@SYSTEM_MAKE_WRAPPER=1 sudo --preserve-env=SYSTEM_MAKE_WRAPPER bash ./install.sh --phase permissions

secureboot: guard-non-root
	@SYSTEM_MAKE_WRAPPER=1 sudo --preserve-env=SYSTEM_MAKE_WRAPPER bash ./install.sh --phase secureboot

sudoers: guard-non-root
	@SYSTEM_MAKE_WRAPPER=1 sudo --preserve-env=SYSTEM_MAKE_WRAPPER bash ./install.sh --phase sudoers

install: guard-non-root
	@SYSTEM_MAKE_WRAPPER=1 sudo --preserve-env=SYSTEM_MAKE_WRAPPER bash ./install.sh --phase all

verify: guard-non-root
	@SYSTEM_MAKE_WRAPPER=1 sudo --preserve-env=SYSTEM_MAKE_WRAPPER bash ./install.sh --phase verify

print-env: guard-non-root
	@SYSTEM_MAKE_WRAPPER=1 bash ./install.sh --phase print-env

nuke: guard-non-root
	@SYSTEM_MAKE_WRAPPER=1 sudo --preserve-env=SYSTEM_MAKE_WRAPPER bash ./install.sh --phase nuke
