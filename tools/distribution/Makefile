.PHONY: all

all:
	@echo "⚙️  Ensuring that GitHub CLI is installed $(PWD)"
	@brew list gh &>/dev/null || brew install gh
ifeq ($(wildcard venv),)
	@echo "⚙️  Creating Python venv in $(PWD)"
	python3 -m venv venv
endif
	@echo "⚙️  Installing pip dependencies in $(PWD)/venv"
	venv/bin/pip3 install -r requirements.txt
