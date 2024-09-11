.PHONY: clean install run test

REPO_ROOT := ../../
include ../utils/common.mk

clean:
	@$(ECHO_SUBTITLE2) "make clean"
	rm -rf "venv"

install:
	@$(ECHO_SUBTITLE2) "make install"
	python3 -m venv venv
	venv/bin/pip3 install -r requirements.txt

run:
	@$(call require_param,PARAMS)
	@$(ECHO_SUBTITLE2) "make run"
	venv/bin/python3 $(PARAMS)

test:
	@$(ECHO_SUBTITLE2) "make test"
	venv/bin/python3 -m pytest tests
