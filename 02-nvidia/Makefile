SHELL := /usr/bin/env bash

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
	./install.sh --phase doctor

install:
	./install.sh --phase all

verify:
	./install.sh --phase verify

nuke:
	./install.sh --phase nuke
