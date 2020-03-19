ifdef ci
		GIT_BRANCH := ${BITRISE_GIT_BRANCH}
else
		GIT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
endif

test:
		@echo "⚙️  Testing Carthage for remote branch: '${GIT_BRANCH}'..."
		@sed "s|REMOTE_GIT_BRANCH|${GIT_BRANCH}|g" Cartfile.src > Cartfile
		rm -rf Carthage/
		carthage update
		@echo "OK 👌"
