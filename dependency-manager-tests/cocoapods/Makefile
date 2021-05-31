GIT_REFERENCE := "branch=\>\'$(shell git rev-parse --abbrev-ref HEAD)\'"
ifneq (${BITRISE_GIT_BRANCH},)
	GIT_REFERENCE := "branch=\>\'${BITRISE_GIT_BRANCH}\'"
endif
ifneq (${BITRISE_GIT_TAG},)
	GIT_REFERENCE := "tag=\>\'${BITRISE_GIT_TAG}\'"
endif

test:
		@echo "⚙️  Configuring CPProject with remote branch: '${GIT_REFERENCE}'..."
		@sed "s|REMOTE_GIT_REFERENCE|${GIT_REFERENCE}|g" Podfile.src > Podfile
		@rm -rf Pods/
		pod update
		@echo "OK 👌"
