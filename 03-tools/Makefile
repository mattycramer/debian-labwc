SHELL := /usr/bin/env bash
RUN_INSTALL = if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh; else sudo bash ./install.sh; fi

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
	@$(RUN_INSTALL) --phase doctor

install:
	@$(RUN_INSTALL) --phase all

verify:
	@$(RUN_INSTALL) --phase verify

nuke:
	@$(RUN_INSTALL) --phase nuke
