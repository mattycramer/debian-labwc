SHELL := /usr/bin/env bash
RUN_INSTALL = if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh; else sudo bash ./install.sh; fi

.PHONY: help doctor detect install render enable verify reconfigure print-env nuke

help:
	@printf '%s\n' \
	  'Targets:' \
	  '  help        Show this message' \
	  '  doctor      Validate platform assumptions' \
	  '  detect      Detect user, GPU, and outputs into .env' \
	  '  install     Run doctor, detect, packages, render, enable, verify' \
	  '  render      Render configs from .env' \
	  '  enable      Install root-owned files and enable services' \
	  '  verify      Check install state' \
	  '  reconfigure Run detect, render, enable, verify' \
	  '  print-env   Print effective env values' \
	  '  nuke        Remove generated state and disable installed wiring'

doctor:
	@$(RUN_INSTALL) --phase doctor

detect:
	@$(RUN_INSTALL) --phase detect

install:
	@$(RUN_INSTALL) --phase all

render:
	@$(RUN_INSTALL) --phase render

enable:
	@$(RUN_INSTALL) --phase enable

verify:
	@$(RUN_INSTALL) --phase verify

reconfigure:
	@$(RUN_INSTALL) --phase detect
	@$(RUN_INSTALL) --phase render
	@$(RUN_INSTALL) --phase enable
	@$(RUN_INSTALL) --phase verify

print-env:
	@$(RUN_INSTALL) --phase print-env

nuke:
	@$(RUN_INSTALL) --phase nuke
