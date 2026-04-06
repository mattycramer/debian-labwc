SHELL := /usr/bin/env bash

.PHONY: help doctor detect install packages render enable verify nuke print-env

help:
	@printf '%s\n' \
	  '09-qbittorrent-nox targets:' \
	  '  doctor    Validate host prerequisites for the hardened qBittorrent-nox module' \
	  '  detect    Capture the invoking user into .env and record torrent mount metadata when available' \
	  '  install   Run doctor, detect, packages, render, enable, and verify' \
	  '  packages  Install qBittorrent-nox and AppArmor tooling from DEBIAN_SUITE' \
	  '  render    Render the managed qBittorrent config, root-mount guard, mount-driven systemd unit, and AppArmor profile' \
	  '  enable    Use the existing hardened torrent account, load AppArmor, and enable the mount-driven service' \
	  '  verify    Verify package state, service hardening, and AppArmor enforcement with disconnected-drive tolerance' \
	  '  nuke      Disable the managed service and remove managed config, helper, AppArmor, and state files' \
	  '  print-env Show the effective managed environment values with secrets redacted'

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
