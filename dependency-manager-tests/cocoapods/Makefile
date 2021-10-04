GIT_REFERENCE := "branch=\>\'$(shell git rev-parse --abbrev-ref HEAD)\'"
ifneq (${BITRISE_GIT_BRANCH},)
	GIT_REFERENCE := "branch=\>\'${BITRISE_GIT_BRANCH}\'"
endif
ifneq (${BITRISE_GIT_TAG},)
	GIT_REFERENCE := "tag=\>\'${BITRISE_GIT_TAG}\'"
endif

GIT_REMOTE := "https://github.com/DataDog/dd-sdk-ios.git"
ifneq (${BITRISEIO_PULL_REQUEST_REPOSITORY_URL},)
	GIT_REMOTE := ${BITRISEIO_PULL_REQUEST_REPOSITORY_URL}
endif

test:
		@echo "⚙️  Configuring CPProject with remote branch: '${GIT_REFERENCE}'..."
		@sed "s|GIT_REFERENCE|${GIT_REFERENCE}|g" Podfile.src | \
		sed "s|GIT_REMOTE|${GIT_REMOTE}|g" > Podfile
		@rm -rf Pods/
		pod update
		@echo "👌 'pod update' OK"
