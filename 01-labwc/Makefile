SHELL := /usr/bin/env bash

.PHONY: help doctor detect install render enable verify reconfigure print-env

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
	  '  print-env   Print effective env values'

doctor:
	./install.sh --phase doctor

detect:
	./install.sh --phase detect

install:
	./install.sh --phase all

render:
	./install.sh --phase render

enable:
	./install.sh --phase enable

verify:
	./install.sh --phase verify

reconfigure:
	./install.sh --phase detect
	./install.sh --phase render
	./install.sh --phase enable
	./install.sh --phase verify

print-env:
	./install.sh --phase print-env
