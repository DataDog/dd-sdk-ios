ifdef ci
		GIT_BRANCH := ${BITRISE_GIT_BRANCH}
else
		GIT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
endif

test:
		@echo "⚙️  Configuring CPProject with remote branch: '${GIT_BRANCH}'..."
		@sed "s|REMOTE_GIT_BRANCH|${GIT_BRANCH}|g" Podfile.src > Podfile
		@rm -rf Pods/
		pod update
		@echo "OK 👌"
