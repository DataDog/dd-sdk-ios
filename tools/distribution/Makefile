.PHONY: clean install test

REPO_ROOT := ../../
include ../utils/common.mk

clean:
	@$(ECHO_SUBTITLE2) "make clean"
	rm -rf "venv"

install:
	@$(ECHO_SUBTITLE2) "make install"
	python3 -m venv venv
	venv/bin/pip3 install -r requirements.txt

test:
	@$(ECHO_SUBTITLE2) "make test"
	venv/bin/python3 -m pytest tests
