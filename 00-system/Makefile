SHELL := /usr/bin/env bash

.PHONY: help doctor mounts permissions sudoers install verify print-env nuke

help:
	@printf '%s\n' \
	  '00-system targets:' \
	  '  help         Show this message' \
	  '  doctor       Validate platform assumptions and resolve the invoking user' \
	  '  mounts       Install generated systemd automount/mount units from mounts.conf' \
	  '  permissions  Create required system paths and repair user ownership/modes' \
	  '  sudoers      Install the hardened invoking-user policy under /etc/sudoers.d' \
	  '  install      Run doctor, mounts, permissions, sudoers, and verify' \
	  '  verify       Check generated mount units, sudoers, and required path permissions' \
	  '  print-env    Print resolved target user/path state' \
	  '  nuke         Remove generated mount units and sudoers policy; directory permissions stay in place'

doctor:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase doctor; else sudo bash ./install.sh --phase doctor; fi

mounts:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase mounts; else sudo bash ./install.sh --phase mounts; fi

permissions:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase permissions; else sudo bash ./install.sh --phase permissions; fi

sudoers:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase sudoers; else sudo bash ./install.sh --phase sudoers; fi

install:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase all; else sudo bash ./install.sh --phase all; fi

verify:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase verify; else sudo bash ./install.sh --phase verify; fi

print-env:
	@bash ./install.sh --phase print-env

nuke:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase nuke; else sudo bash ./install.sh --phase nuke; fi
