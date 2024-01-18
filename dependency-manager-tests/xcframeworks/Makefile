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
		@pwd
		@echo "⚙️  Configuring XCProject with remote branch: '${GIT_REFERENCE}'..."
		@echo "Creating symbolic link to dd-sdk-ios"
		@rm -rf dd-sdk-ios
		@ln -s ../../../dd-sdk-ios dd-sdk-ios
		# @git clone --depth 1 --branch ${GIT_REFERENCE} ${GIT_REMOTE}
		@echo "🧪 Build xcframeworks"
		@cd dd-sdk-ios && tools/distribution/build-xcframework.sh
		@echo "🧪 Check if expected frameworks exist in $(PWD)/dd-sdk-ios/build/xcframeworks"
		@[ -e "dd-sdk-ios/build/xcframeworks/DatadogCore.xcframework" ] && echo "DatadogCore.xcframework - OK" || { echo "DatadogCore.xcframework - missing"; false; }
		@[ -e "dd-sdk-ios/build/xcframeworks/DatadogLogs.xcframework" ] && echo "DatadogLogs.xcframework - OK" || { echo "DatadogLogs.xcframework - missing"; false; }
		@[ -e "dd-sdk-ios/build/xcframeworks/DatadogTrace.xcframework" ] && echo "DatadogTrace.xcframework - OK" || { echo "DatadogTrace.xcframework - missing"; false; }
		@[ -e "dd-sdk-ios/build/xcframeworks/DatadogRUM.xcframework" ] && echo "DatadogRUM.xcframework - OK" || { echo "DatadogRUM.xcframework - missing"; false; }
		@[ -e "dd-sdk-ios/build/xcframeworks/DatadogSessionReplay.xcframework" ] && echo "DatadogSessionReplay.xcframework - OK" || { echo "DatadogSessionReplay.xcframework - missing"; false; }
		@[ -e "dd-sdk-ios/build/xcframeworks/DatadogObjc.xcframework" ] && echo "DatadogObjc.xcframework - OK" || { echo "DatadogObjc.xcframework - missing"; false; }
		@[ -e "dd-sdk-ios/build/xcframeworks/DatadogCrashReporting.xcframework" ] && echo "DatadogCrashReporting.xcframework - OK" || { echo "DatadogCrashReporting.xcframework - missing"; false; }
		@[ -e "dd-sdk-ios/build/xcframeworks/CrashReporter.xcframework" ] && echo "CrashReporter.xcframework - OK" || { echo "CrashReporter.xcframework - missing"; false; }
		@[ -e "dd-sdk-ios/build/xcframeworks/OpenTelemetryApi.xcframework" ] && echo "OpenTelemetryApi.xcframework - OK" || { echo "OpenTelemetryApi.xcframework - missing"; false; }
		@echo "🧪 SUCCEEDED"
