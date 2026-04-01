SHELL := /usr/bin/env bash

.PHONY: help doctor repo packages config install verify print-env nuke

help:
	@printf '%s\n' \
	  'Targets:' \
	  '  help    Show this message' \
	  '  doctor  Validate platform assumptions' \
	  '  repo    Validate Debian contrib and configure the NVIDIA upstream repository' \
	  '  packages Install Debian prerequisites plus NVIDIA upstream driver and CUDA toolkit' \
	  '  config  Render NVIDIA module configuration and refresh initramfs' \
	  '  install Run repo + packages + config + verify' \
	  '  verify  Verify upstream packages, DRM modeset, switcherooctl, and CUDA state' \
	  '  print-env Show resolved installer configuration' \
	  '  nuke    Remove NVIDIA/CUDA packages and managed config'

doctor:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase doctor; else sudo bash ./install.sh --phase doctor; fi

repo:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase repo; else sudo bash ./install.sh --phase repo; fi

packages:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase packages; else sudo bash ./install.sh --phase packages; fi

config:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase config; else sudo bash ./install.sh --phase config; fi

install:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase all; else sudo bash ./install.sh --phase all; fi

verify:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase verify; else sudo bash ./install.sh --phase verify; fi

print-env:
	@bash ./install.sh --phase print-env

nuke:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase nuke; else sudo bash ./install.sh --phase nuke; fi
