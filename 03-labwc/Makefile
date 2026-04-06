SHELL := /usr/bin/env bash

.PHONY: help doctor detect install render build-sources enable verify reconfigure print-env nuke

help:
	@printf '%s\n' \
	  'Targets:' \
	  '  help        Show this message' \
	  '  doctor      Validate platform assumptions' \
	  '  detect      Detect user, GPU, and outputs into .env' \
	  '  install     Install 03-labwc on a fresh system after 01-dbus-broker is staged; all apt package installs target DEBIAN_SUITE and source mode rebuilds wlroots/labwc from Debian source packages' \
	  '  render      Render configs from .env' \
	  '  build-sources Rebuild wlroots/labwc from Debian source packages plus pinned extras from source, or install the pinned artifact path for the extras' \
	  '  enable      Install root-owned files and enable services' \
	  '  verify      Verify the selected source/artifact install path, greeter wiring, and session activation contracts' \
	  '  reconfigure Re-render 03-labwc after 01-dbus-broker is already staged; runs detect, render, build-sources, enable, verify' \
	  '  print-env   Print effective env values' \
	  '  nuke        Remove generated state and disable installed wiring'

doctor:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase doctor; else sudo bash ./install.sh --phase doctor; fi

detect:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase detect; else sudo bash ./install.sh --phase detect; fi

install:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase all; else sudo bash ./install.sh --phase all; fi

render:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase render; else sudo bash ./install.sh --phase render; fi

build-sources:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase build-sources; else sudo bash ./install.sh --phase build-sources; fi

enable:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase enable; else sudo bash ./install.sh --phase enable; fi

verify:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase verify; else sudo bash ./install.sh --phase verify; fi

reconfigure:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase detect; else sudo bash ./install.sh --phase detect; fi
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase render; else sudo bash ./install.sh --phase render; fi
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase build-sources; else sudo bash ./install.sh --phase build-sources; fi
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase enable; else sudo bash ./install.sh --phase enable; fi
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase verify; else sudo bash ./install.sh --phase verify; fi

print-env:
	@bash ./install.sh --phase print-env

nuke:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase nuke; else sudo bash ./install.sh --phase nuke; fi
