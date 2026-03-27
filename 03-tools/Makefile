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
	./install.sh --phase doctor

install:
	./install.sh --phase all

verify:
	./install.sh --phase verify

nuke:
	./install.sh --phase nuke
