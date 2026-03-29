SHELL := /usr/bin/env bash

.PHONY: help doctor fstab permissions install verify print-env nuke

help:
	@printf '%s\n' \
	  '00-system targets:' \
	  '  help         Show this message' \
	  '  doctor       Validate platform assumptions and resolve the invoking user' \
	  '  fstab        Sync managed /etc/fstab entries from fstab.env' \
	  '  permissions  Create required system paths and repair user ownership/modes' \
	  '  install      Run doctor, fstab, permissions, and verify' \
	  '  verify       Check managed fstab state and required path permissions' \
	  '  print-env    Print resolved target user/path state' \
	  '  nuke         Remove the managed fstab block; directory permissions stay in place'

doctor:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase doctor; else sudo bash ./install.sh --phase doctor; fi

fstab:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase fstab; else sudo bash ./install.sh --phase fstab; fi

permissions:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase permissions; else sudo bash ./install.sh --phase permissions; fi

install:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase all; else sudo bash ./install.sh --phase all; fi

verify:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase verify; else sudo bash ./install.sh --phase verify; fi

print-env:
	@bash ./install.sh --phase print-env

nuke:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase nuke; else sudo bash ./install.sh --phase nuke; fi
