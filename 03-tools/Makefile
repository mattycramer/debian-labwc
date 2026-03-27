SHELL := /usr/bin/env bash

.PHONY: help doctor install verify nuke

help:
	@printf '%s\n' \
	  'Targets:' \
	  '  help    Show this message' \
	  '  doctor  Validate platform assumptions' \
	  '  install Configure repos, install tools, and render configs' \
	  '  verify  Verify packages, sources, and mpv config' \
	  '  nuke    Remove installed tooling and repo files'

doctor:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase doctor; else sudo bash ./install.sh --phase doctor; fi

install:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase all; else sudo bash ./install.sh --phase all; fi

verify:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase verify; else sudo bash ./install.sh --phase verify; fi

nuke:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase nuke; else sudo bash ./install.sh --phase nuke; fi
