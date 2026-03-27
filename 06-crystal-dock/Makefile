SHELL := /usr/bin/env bash

.PHONY: help doctor install render verify nuke print-env

help:
	@printf '%s\n' \
	  '06-crystal-dock targets:' \
	  '  doctor    Validate host prerequisites for Crystal Dock install' \
	  '  install   Install Crystal Dock, render Labwc config, and wire autostart' \
	  '  render    Re-render the managed Crystal Dock config and Labwc hook' \
	  '  verify    Verify installed package and managed files' \
	  '  nuke      Remove Crystal Dock package, wrapper, and managed config' \
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
