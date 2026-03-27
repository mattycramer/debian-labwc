SHELL := /usr/bin/env bash

.PHONY: help doctor install render verify nuke print-env

help:
	@printf '%s\n' \
	  '06-nwg-dock targets:' \
	  '  doctor    Validate host prerequisites for nwg-dock build/install' \
	  '  install   Build/install nwg-dock, render config, and wire guarded autostart' \
	  '  render    Re-render managed nwg-dock config and Labwc wrapper' \
	  '  verify    Verify managed nwg-dock files and wrappers' \
	  '  nuke      Remove managed nwg-dock binary, data, wrapper, and config' \
	  '  print-env Show the effective managed environment values'

doctor:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase doctor; else sudo bash ./install.sh --phase doctor; fi

install:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase all; else sudo bash ./install.sh --phase all; fi

render:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase render; else sudo bash ./install.sh --phase render; fi

verify:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase verify; else sudo bash ./install.sh --phase verify; fi

nuke:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase nuke; else sudo bash ./install.sh --phase nuke; fi

print-env:
	@bash ./install.sh --phase print-env
