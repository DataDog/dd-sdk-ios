GIT_REFERENCE := $(shell git rev-parse --abbrev-ref HEAD)
ifneq (${BITRISE_GIT_BRANCH},)
	GIT_REFERENCE := ${BITRISE_GIT_BRANCH}
endif
ifneq (${BITRISE_GIT_TAG},)
	GIT_REFERENCE := ${BITRISE_GIT_TAG}
endif

test:
		@echo "⚙️  Configuring CTProject with remote branch: '${GIT_REFERENCE}'..."
		@sed "s|REMOTE_GIT_REFERENCE|${GIT_REFERENCE}|g" Cartfile.src > Cartfile
		@rm -rf Carthage/
		@echo "🧪 Run 'carthage update'"
		@carthage update --platform iOS --use-xcframeworks
		@echo "🧪 Check if expected frameworks exist in $(PWD)/Carthage/Build/"
		@[ -e "Carthage/Build/Datadog.xcframework" ] && echo "Datadog.xcframework - OK" || { echo "Datadog.xcframework - missing"; false; }
		@[ -e "Carthage/Build/DatadogObjc.xcframework" ] && echo "DatadogObjc.xcframework - OK" || { echo "DatadogObjc.xcframework - missing"; false; }
		@[ -e "Carthage/Build/DatadogCrashReporting.xcframework" ] && echo "DatadogCrashReporting.xcframework - OK" || { echo "DatadogCrashReporting.xcframework - missing"; false; }
		@[ -e "Carthage/Build/Kronos.xcframework" ] && echo "Kronos.xcframework - OK" || { echo "Kronos.xcframework - missing"; false; }
		@[ -e "Carthage/Build/CrashReporter.xcframework" ] && echo "CrashReporter.xcframework - OK" || { echo "CrashReporter.xcframework - missing"; false; }
		@echo "🧪 SUCCEEDED"
