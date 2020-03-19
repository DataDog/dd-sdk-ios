ifdef ci
		GIT_BRANCH := ${BITRISE_GIT_BRANCH}
else
		GIT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
endif

test:
		@echo "⚙️  Testing SPM for remote branch: '${GIT_BRANCH}'..."
		@sed "s|REMOTE_GIT_BRANCH|${GIT_BRANCH}|g" Package.swift.src > Package.swift
		swift package update
		swift build
		@echo "OK 👌"
