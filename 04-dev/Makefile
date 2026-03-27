.PHONY: help doctor install verify nuke print-env

help:
	@printf '%s\n' \
	  '04-dev targets:' \
	  '  doctor    Validate host prerequisites' \
	  '  install   Install dev packages, Node.js 25+, and pnpm' \
	  '  verify    Verify installed packages and managed binaries' \
	  '  nuke      Remove managed dev packages and Node.js runtime' \
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
	@if [ "$$(id -u)" -eq 0 ]; then bash ./install.sh --phase print-env; else sudo bash ./install.sh --phase print-env; fi
