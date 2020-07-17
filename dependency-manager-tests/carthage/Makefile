ifdef ci
		GIT_BRANCH := ${BITRISE_GIT_BRANCH}
else
		GIT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
endif

PWD := $(shell pwd)

test:
		@echo "⚙️  Configuring CTProject with remote branch: '${GIT_BRANCH}'..."
		@sed "s|REMOTE_GIT_BRANCH|${GIT_BRANCH}|g" Cartfile.src > Cartfile
		@rm -rf Carthage/
		@echo "🧪 Run 'carthage update'"
		@carthage update --platform iOS
		@echo "🧪 Check if expected frameworks exist in $(PWD)/Carthage/Build/iOS"
		@[ -e "Carthage/Build/iOS/Datadog.framework" ] && echo "Datadog.framework - OK" || { echo "Datadog.framework - missing"; false; }
		@[ -e "Carthage/Build/iOS/DatadogObjc.framework" ] && echo "DatadogObjc.framework - OK" || { echo "DatadogObjc.framework - missing"; false; }
		@echo "🧪 SUCCEEDED"
