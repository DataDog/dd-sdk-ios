GIT_REFERENCE := $(shell git rev-parse --abbrev-ref HEAD)
ifneq (${BITRISE_GIT_BRANCH},)
	GIT_REFERENCE := ${BITRISE_GIT_BRANCH}
endif
ifneq (${BITRISE_GIT_TAG},)
	GIT_REFERENCE := ${BITRISE_GIT_TAG}
endif

GIT_REMOTE := "DataDog/dd-sdk-ios"
ifneq (${BITRISEIO_PULL_REQUEST_REPOSITORY_URL},)
	GIT_REMOTE := ${BITRISEIO_PULL_REQUEST_REPOSITORY_URL}
endif

test:
		@echo "⚙️  Configuring CTProject with remote branch: '${GIT_REFERENCE}'..."

		@sed "s|GIT_REFERENCE|${GIT_REFERENCE}|g" Cartfile.src | \
		sed "s|GIT_REMOTE|${GIT_REMOTE}|g" > Cartfile
		@rm -rf Carthage/
		@echo "🧪 Run 'carthage updaopente'"
		@carthage update --platform iOS,tvOS --use-xcframeworks
		@echo "🧪 Check if expected frameworks exist in $(PWD)/Carthage/Build/"
		@[ -e "Carthage/Build/DatadogInternal.xcframework" ] && echo "DatadogInternal.xcframework - OK" || { echo "DatadogInternal.xcframework - missing"; false; }
		@[ -e "Carthage/Build/DatadogCore.xcframework" ] && echo "DatadogCore.xcframework - OK" || { echo "DatadogCore.xcframework - missing"; false; }
		@[ -e "Carthage/Build/DatadogLogs.xcframework" ] && echo "DatadogLogs.xcframework - OK" || { echo "DatadogLogs.xcframework - missing"; false; }
		@[ -e "Carthage/Build/DatadogTrace.xcframework" ] && echo "DatadogTrace.xcframework - OK" || { echo "DatadogTrace.xcframework - missing"; false; }
		@[ -e "Carthage/Build/DatadogRUM.xcframework" ] && echo "DatadogRUM.xcframework - OK" || { echo "DatadogRUM.xcframework - missing"; false; }
		@[ -e "Carthage/Build/DatadogSessionReplay.xcframework" ] && echo "DatadogSessionReplay.xcframework - OK" || { echo "DatadogSessionReplay.xcframework - missing"; false; }
		@[ -e "Carthage/Build/DatadogObjc.xcframework" ] && echo "DatadogObjc.xcframework - OK" || { echo "DatadogObjc.xcframework - missing"; false; }
		@[ -e "Carthage/Build/DatadogCrashReporting.xcframework" ] && echo "DatadogCrashReporting.xcframework - OK" || { echo "DatadogCrashReporting.xcframework - missing"; false; }
		@[ -e "Carthage/Build/CrashReporter.xcframework" ] && echo "CrashReporter.xcframework - OK" || { echo "CrashReporter.xcframework - missing"; false; }
		@[ -e "Carthage/Build/DatadogWebViewTracking.xcframework" ] && echo "DatadogWebViewTracking.xcframework - OK" || { echo "DatadogWebViewTracking.xcframework - missing"; false; }
		@[ -e "Carthage/Build/OpenTelemetryApi.xcframework" ] && echo "OpenTelemetryApi.xcframework - OK" || { echo "OpenTelemetryApi.xcframework - missing"; false; }
		@echo "🧪 SUCCEEDED"
