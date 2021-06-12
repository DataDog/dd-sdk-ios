.PHONY: all

all:
	@brew list gh &>/dev/null || brew install gh
ifeq ($(wildcard venv),)
	@echo "⚙️  Creating Python venv in $(PWD)"
	python3 -m venv venv
endif
	venv/bin/pip3 install GitPython==3.1.14
	venv/bin/python3 dogfood.py
