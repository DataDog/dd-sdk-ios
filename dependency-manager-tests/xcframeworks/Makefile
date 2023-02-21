GIT_REFERENCE := $(shell git rev-parse --abbrev-ref HEAD)
ifneq (${BITRISE_GIT_BRANCH},)
	GIT_REFERENCE := ${BITRISE_GIT_BRANCH}
endif
ifneq (${BITRISE_GIT_TAG},)
	GIT_REFERENCE := ${BITRISE_GIT_TAG}
endif

GIT_REMOTE := "https://github.com/DataDog/dd-sdk-ios.git"
ifneq (${BITRISEIO_PULL_REQUEST_REPOSITORY_URL},)
	GIT_REMOTE := ${BITRISEIO_PULL_REQUEST_REPOSITORY_URL}
endif

test:
		@echo "⚙️  Configuring XCProject with remote branch: '${GIT_REFERENCE}'..."
		@rm -rf dd-sdk-ios/
		@git clone --depth 1 --branch ${GIT_REFERENCE} ${GIT_REMOTE}
		@echo "🧪 Build xcframeworks"
		@cd dd-sdk-ios && tools/distribution/build-xcframework.sh
		@echo "🧪 Check if expected frameworks exist in $(PWD)/dd-sdk-ios/build/xcframeworks"
		@[ -e "dd-sdk-ios/build/xcframeworks/Datadog.xcframework" ] && echo "Datadog.xcframework - OK" || { echo "Datadog.xcframework - missing"; false; }
		@[ -e "dd-sdk-ios/build/xcframeworks/DatadogObjc.xcframework" ] && echo "DatadogObjc.xcframework - OK" || { echo "DatadogObjc.xcframework - missing"; false; }
		@[ -e "dd-sdk-ios/build/xcframeworks/DatadogCrashReporting.xcframework" ] && echo "DatadogCrashReporting.xcframework - OK" || { echo "DatadogCrashReporting.xcframework - missing"; false; }
		@[ -e "dd-sdk-ios/build/xcframeworks/CrashReporter.xcframework" ] && echo "CrashReporter.xcframework - OK" || { echo "CrashReporter.xcframework - missing"; false; }
		@echo "🧪 SUCCEEDED"
