ifdef ci
		GIT_BRANCH := ${BITRISE_GIT_BRANCH}
else
		GIT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
endif

EXPECTED_FRAMEWORKS := \
	Carthage/Build/iOS/Datadog.framework \
	Carthage/Build/iOS/DatadogObjc.framework \
	Carthage/Build/iOS/OpenTracing.framework

FRAMEWORKS_MISSING := $(shell $(foreach framework,$(EXPECTED_FRAMEWORKS),test -e "$(framework)" || echo "$(framework)";))

test:
		@echo "⚙️  Testing Carthage for remote branch: '${GIT_BRANCH}'..."
		@sed "s|REMOTE_GIT_BRANCH|${GIT_BRANCH}|g" Cartfile.src > Cartfile
		@rm -rf Carthage/

		@echo "🧪 Run 'carthage update'"
		carthage update

		@echo "🧪 Check if expected frameworks exist"
ifneq ($(FRAMEWORKS_MISSING),)
	@echo "🔥 Frameworks missing: $(FRAMEWORKS_MISSING)"
	@echo "🧪 FAILED"
	@false
endif
		@echo "🧪 SUCCEEDED"
