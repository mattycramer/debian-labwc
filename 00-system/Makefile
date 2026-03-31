SHELL := /usr/bin/env bash

.PHONY: help guard-non-root doctor mounts permissions sudoers install verify print-env nuke

help:
	@printf '%s\n' \
	  '00-system targets:' \
	  '  NOTE:        Run make as a non-root user; do not use sudo make' \
	  '  help         Show this message' \
	  '  doctor       Validate platform assumptions and resolve the invoking user' \
	  '  mounts       Install four device-gated top-level g-drive automount/mount units from mounts.conf' \
	  '  permissions  Create the hardened torrent account, add the invoking user to torrent, and repair required path ownership/modes' \
	  '  sudoers      Install the hardened invoking-user policy under /etc/sudoers.d' \
	  '  install      Run doctor, mounts, permissions, sudoers, and verify' \
	  '  verify       Check generated mount units, sudoers, and required path permissions' \
	  '  print-env    Print resolved target user/path state' \
	  '  nuke         Remove generated mount units and sudoers policy; directory permissions stay in place'

guard-non-root:
	@if [ "$$(id -u)" -eq 0 ]; then \
	  printf '%s\n' "Refusing to run 00-system from a root make process. Run 'make <target>' as a non-root user; do not use sudo make." >&2; \
	  exit 1; \
	fi

doctor: guard-non-root
	@SYSTEM_MAKE_WRAPPER=1 sudo --preserve-env=SYSTEM_MAKE_WRAPPER bash ./install.sh --phase doctor

mounts: guard-non-root
	@SYSTEM_MAKE_WRAPPER=1 sudo --preserve-env=SYSTEM_MAKE_WRAPPER bash ./install.sh --phase mounts

permissions: guard-non-root
	@SYSTEM_MAKE_WRAPPER=1 sudo --preserve-env=SYSTEM_MAKE_WRAPPER bash ./install.sh --phase permissions

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
