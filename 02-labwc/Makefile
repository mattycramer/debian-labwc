SHELL := /usr/bin/env bash

.PHONY: help doctor detect install render enable extras reconfigure print-env nuke

help:
	@printf '%s\n' \
	  'Targets:' \
	  '  help        Show this message' \
	  '  doctor      Validate platform assumptions' \
	  '  detect      Detect user, GPU, and outputs into .env' \
	  '  install     Run doctor, detect, packages, render, enable' \
	  '  render      Render configs from .env' \
	  '  enable      Install root-owned files and enable services' \
	  '  extras      Build and install optional network-fetched extras' \
	  '  reconfigure Run detect, render, enable' \
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

enable:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase enable; else sudo bash ./install.sh --phase enable; fi

extras:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase extras; else sudo bash ./install.sh --phase extras; fi

reconfigure:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase detect; else sudo bash ./install.sh --phase detect; fi
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase render; else sudo bash ./install.sh --phase render; fi
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase enable; else sudo bash ./install.sh --phase enable; fi

print-env:
	@bash ./install.sh --phase print-env

nuke:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase nuke; else sudo bash ./install.sh --phase nuke; fi
