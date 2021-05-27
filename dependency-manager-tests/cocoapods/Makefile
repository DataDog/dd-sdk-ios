GIT_BRANCH := "branch=\>\'$(shell git rev-parse --abbrev-ref HEAD)\'"
ifneq (${BITRISE_GIT_BRANCH},)
	GIT_BRANCH := "branch=\>\'${BITRISE_GIT_BRANCH}\'"
endif
ifneq (${BITRISE_GIT_TAG},)
	GIT_BRANCH := "tag=\>\'${BITRISE_GIT_TAG}\'"
endif

test:
		@echo "⚙️  Configuring CPProject with remote branch: '${GIT_BRANCH}'..."
		@sed "s|REMOTE_GIT_BRANCH|${GIT_BRANCH}|g" Podfile.src > Podfile
		@rm -rf Pods/
		pod update
		@echo "OK 👌"
