ifeq (${ci}, true)
		GIT_BRANCH := ${BITRISE_GIT_BRANCH}
else
		GIT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
endif

test:
		@echo "⚙️  Configuring CTProject with remote branch: '${GIT_BRANCH}'..."
		@sed "s|REMOTE_GIT_BRANCH|${GIT_BRANCH}|g" Cartfile.src > Cartfile
		@rm -rf Carthage/
		@echo "🧪 Run 'carthage update'"
		@carthage update --platform iOS --use-xcframeworks
		@echo "🧪 Check if expected frameworks exist in $(PWD)/Carthage/Build/"
		@[ -e "Carthage/Build/Datadog.xcframework" ] && echo "Datadog.xcframework - OK" || { echo "Datadog.xcframework - missing"; false; }
		@[ -e "Carthage/Build/DatadogObjc.xcframework" ] && echo "DatadogObjc.xcframework - OK" || { echo "DatadogObjc.xcframework - missing"; false; }
		@[ -e "Carthage/Build/Kronos.xcframework" ] && echo "Kronos.xcframework - OK" || { echo "Kronos.xcframework - missing"; false; }
		@echo "🧪 SUCCEEDED"
