SHELL := /usr/bin/env bash

.PHONY: help doctor detect install packages render enable verify nuke print-env

help:
	@printf '%s\n' \
	  '09-dbus-broker targets:' \
	  '  doctor    Validate host prerequisites for compiled dbus-broker deployment on Debian trixie' \
	  '  detect    Detect invoking user and current system/user dbus.service fragments into .env' \
	  '  install   Run doctor, detect, packages, render, enable, and verify' \
	  '  packages  Install runtime dependencies with apt -t sid' \
	  '  render    Download, verify, extract, and install the pinned compiled release, unit overrides, and D-Bus compatibility aliases' \
	  '  enable    Reload systemd and stage the managed broker units for next reboot/login without restarting the current buses' \
	  '  verify    Verify provenance, installed files, unit overrides, compatibility aliases, and broker-backed or staged runtime state' \
	  '  nuke      Remove managed unit overrides and unmanaged artifacts, keep package-owned files, and stage fallback dbus.service units without restarting active buses' \
	  '  print-env Show effective environment values and detected state in 09-dbus-broker/.env'

doctor:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase doctor; else sudo bash ./install.sh --phase doctor; fi

detect:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase detect; else sudo bash ./install.sh --phase detect; fi

install:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase all; else sudo bash ./install.sh --phase all; fi

packages:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase packages; else sudo bash ./install.sh --phase packages; fi

render:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase render; else sudo bash ./install.sh --phase render; fi

enable:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase enable; else sudo bash ./install.sh --phase enable; fi

verify:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase verify; else sudo bash ./install.sh --phase verify; fi

nuke:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase nuke; else sudo bash ./install.sh --phase nuke; fi

print-env:
	@bash ./install.sh --phase print-env
