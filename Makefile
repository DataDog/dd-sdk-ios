all: tools dependencies xcodeproj-httpservermock templates
.PHONY : tools

tools:
		@echo "⚙️  Installing tools..."
		@brew list swiftlint &>/dev/null || brew install swiftlint
		@echo "OK 👌"

# The release version of `dd-sdk-swift-testing` to use for tests instrumentation.
DD_SDK_SWIFT_TESTING_VERSION = 0.5.1

define DD_SDK_TESTING_XCCONFIG_CI
FRAMEWORK_SEARCH_PATHS=$$(inherited) $$(SRCROOT)/../instrumented-tests/DatadogSDKTesting.xcframework/ios-arm64_x86_64-simulator/\n
LD_RUNPATH_SEARCH_PATHS=$$(inherited) $$(SRCROOT)/../instrumented-tests/DatadogSDKTesting.xcframework/ios-arm64_x86_64-simulator/\n
OTHER_LDFLAGS=$$(inherited) -framework DatadogSDKTesting\n
DD_TEST_RUNNER=1\n
DD_SDK_SWIFT_TESTING_SERVICE=dd-sdk-ios\n
DD_SDK_SWIFT_TESTING_CLIENT_TOKEN=${DD_SDK_SWIFT_TESTING_CLIENT_TOKEN}\n
DD_SDK_SWIFT_TESTING_ENV=ci\n
endef
export DD_SDK_TESTING_XCCONFIG_CI

dependencies:
		@echo "⚙️  Installing dependencies..."
		@carthage bootstrap --platform iOS
ifeq (${ci}, true)
		@echo $$DD_SDK_TESTING_XCCONFIG_CI > xcconfigs/DatadogSDKTesting.local.xcconfig;
endif
		@brew list gh &>/dev/null || brew install gh
		@rm -rf instrumented-tests/DatadogSDKTesting.xcframework
		@rm -rf instrumented-tests/DatadogSDKTesting.zip
		@rm -rf instrumented-tests/LICENSE
		@gh release download ${DD_SDK_SWIFT_TESTING_VERSION} -D instrumented-tests -R https://github.com/DataDog/dd-sdk-swift-testing -p "DatadogSDKTesting.zip"
		@unzip instrumented-tests/DatadogSDKTesting.zip -d instrumented-tests
		@[ -e "instrumented-tests/DatadogSDKTesting.xcframework" ] && echo "DatadogSDKTesting.xcframework - OK" || { echo "DatadogSDKTesting.xcframework - missing"; exit 1; }

xcodeproj-httpservermock:
		@echo "⚙️  Generating 'HTTPServerMock.xcodeproj'..."
		@cd instrumented-tests/http-server-mock/ && swift package generate-xcodeproj
		@echo "OK 👌"

templates:
		@echo "⚙️  Installing Xcode templates..."
		./tools/xcode-templates/install-xcode-templates.sh
		@echo "OK 👌"

# Tests if current branch ships a valid SPM package.
test-spm:
		@cd dependency-manager-tests/spm && $(MAKE)

# Tests if current branch ships a valid Carthage project.
test-carthage:
		@cd dependency-manager-tests/carthage && $(MAKE)

# Tests if current branch ships a valid Cocoapods project.
test-cocoapods:
		@cd dependency-manager-tests/cocoapods && $(MAKE)

# Generate RUM data models from rum-events-format JSON Schemas
rum-models-generate:
		@echo "⚙️  Generating RUM models..."
		./tools/rum-models-generator/run.sh generate
		@echo "OK 👌"

# Verify if RUM data models follow rum-events-format JSON Schemas
rum-models-verify:
		@echo "🧪  Verifying RUM models..."
		./tools/rum-models-generator/run.sh verify
		@echo "OK 👌"

# Generate api-surface files for Datadog and DatadogObjc.
api-surface:
		@cd tools/api-surface/ && swift build --configuration release
		@echo "Generating api-surface-swift"
		./tools/api-surface/.build/x86_64-apple-macosx/release/api-surface workspace --workspace-name Datadog.xcworkspace --scheme Datadog --path . > api-surface-swift
		@echo "Generating api-surface-objc"
		./tools/api-surface/.build/x86_64-apple-macosx/release/api-surface workspace --workspace-name Datadog.xcworkspace --scheme DatadogObjc --path . > api-surface-objc

bump:
		@read -p "Enter version number: " version;  \
		echo "// GENERATED FILE: Do not edit directly\n\ninternal let sdkVersion = \"$$version\"" > Sources/Datadog/Versioning.swift; \
		sed "s/__DATADOG_VERSION__/$$version/g" DatadogSDK.podspec.src > DatadogSDK.podspec; \
		sed "s/__DATADOG_VERSION__/$$version/g" DatadogSDKObjc.podspec.src > DatadogSDKObjc.podspec; \
		git add . ; \
		git commit -m "Bumped version to $$version"; \
		echo Bumped version to $$version

ship:
		pod spec lint DatadogSDK.podspec
		pod trunk push DatadogSDK.podspec
		pod repo update
		pod spec lint DatadogSDKObjc.podspec
		pod trunk push DatadogSDKObjc.podspec
