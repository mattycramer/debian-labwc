.PHONY: help doctor install verify nuke print-env

help:
	@printf '%s\n' \
	  '06-security targets:' \
	  '  doctor    Validate host prerequisites' \
	  '  install   Install DEBIAN_SUITE bootstrap packages, then configure nftables, CrowdSec, and AIDE' \
	  '  verify    Verify versions, files, and enabled services' \
	  '  nuke      Remove managed security configs and packages' \
	  '  print-env Show the effective managed environment values'

doctor:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase doctor; else sudo bash ./install.sh --phase doctor; fi

install:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase all; else sudo bash ./install.sh --phase all; fi

verify:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase verify; else sudo bash ./install.sh --phase verify; fi

nuke:
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase nuke; else sudo bash ./install.sh --phase nuke; fi

print-env:
	@bash ./install.sh --phase print-env
