SHELL := /usr/bin/env bash
RUN_INSTALL = if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh; else sudo bash ./install.sh; fi

.PHONY: help doctor install verify nuke

help:
	@printf '%s\n' \
	  'Targets:' \
	  '  help    Show this message' \
	  '  doctor  Validate platform assumptions' \
	  '  install Install NVIDIA packages and headers' \
	  '  verify  Verify NVIDIA install prerequisites and package state' \
	  '  nuke    Remove NVIDIA packages'

doctor:
	@$(RUN_INSTALL) --phase doctor

install:
	@$(RUN_INSTALL) --phase all

verify:
	@$(RUN_INSTALL) --phase verify

nuke:
	@$(RUN_INSTALL) --phase nuke
