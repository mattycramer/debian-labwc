SHELL := /usr/bin/env bash

.PHONY: help doctor detect install packages render enable verify reconfigure print-env nuke

help:
	@printf '%s\n' \
	  '08-maintenance targets:' \
	  '  doctor      Validate host prerequisites for Btrfs maintenance and GRUB snapshot wiring' \
	  '  detect      Detect the root Btrfs filesystem, mounted Btrfs sources, and Btrfs mountpoints into .env' \
	  '  install     Run doctor, detect, package install, render, enable, and verify' \
	  '  packages    Install the required maintenance packages' \
	  '  render      Render Timeshift, grub-btrfs, and btrfsmaintenance configuration' \
	  '  enable      Install grub-btrfs, update GRUB, and enable timers/services' \
	  '  verify      Verify installed files, schedules, and GRUB integration' \
	  '  reconfigure Run detect, render, enable, and verify' \
	  '  nuke        Remove managed maintenance wiring and uninstall managed packages' \
	  '  print-env   Print the effective managed environment values'

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

reconfigure:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase detect; else sudo bash ./install.sh --phase detect; fi
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase render; else sudo bash ./install.sh --phase render; fi
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase enable; else sudo bash ./install.sh --phase enable; fi
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase verify; else sudo bash ./install.sh --phase verify; fi

print-env:
	@bash ./install.sh --phase print-env

nuke:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase nuke; else sudo bash ./install.sh --phase nuke; fi
