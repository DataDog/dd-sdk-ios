all: dependencies templates

# The release version of `dd-sdk-swift-testing` to use for tests instrumentation.
DD_SDK_SWIFT_TESTING_VERSION = 2.3.0

define DD_SDK_TESTING_XCCONFIG_CI
FRAMEWORK_SEARCH_PATHS[sdk=iphonesimulator*]=$$(inherited) $$(SRCROOT)/../instrumented-tests/DatadogSDKTesting.xcframework/ios-arm64_x86_64-simulator/\n
LD_RUNPATH_SEARCH_PATHS[sdk=iphonesimulator*]=$$(inherited) $$(SRCROOT)/../instrumented-tests/DatadogSDKTesting.xcframework/ios-arm64_x86_64-simulator/\n
FRAMEWORK_SEARCH_PATHS[sdk=appletvsimulator*]=$$(inherited) $$(SRCROOT)/../instrumented-tests/DatadogSDKTesting.xcframework/tvos-arm64_x86_64-simulator/\n
LD_RUNPATH_SEARCH_PATHS[sdk=appletvsimulator*]=$$(inherited) $$(SRCROOT)/../instrumented-tests/DatadogSDKTesting.xcframework/tvos-arm64_x86_64-simulator/\n
OTHER_LDFLAGS[sdk=iphonesimulator*]=$$(inherited) -framework DatadogSDKTesting\n
OTHER_LDFLAGS[sdk=appletvsimulator*]=$$(inherited) -framework DatadogSDKTesting\n
DD_TEST_RUNNER=1\n
DD_SDK_SWIFT_TESTING_SERVICE=dd-sdk-ios\n
DD_SDK_SWIFT_TESTING_APIKEY=${DD_SDK_SWIFT_TESTING_APIKEY}\n
DD_SDK_SWIFT_TESTING_ENV=ci\n
DD_SDK_SWIFT_TESTING_APPLICATION_KEY=${DD_SDK_SWIFT_TESTING_APPLICATION_KEY}\n
endef
export DD_SDK_TESTING_XCCONFIG_CI

define DD_SDK_BASE_XCCONFIG
// Active compilation conditions - only enabled on local machine:\n
// - DD_SDK_ENABLE_EXPERIMENTAL_APIS - enables APIs which are not available in released version of the SDK\n
// - DD_SDK_COMPILED_FOR_TESTING - conditions the SDK code compiled for testing\n
SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) DD_SDK_ENABLE_EXPERIMENTAL_APIS DD_SDK_COMPILED_FOR_TESTING\n
\n
// To build only active architecture for all configurations. This gives us ~10% build time gain\n
// in targets which do not use 'Debug' configuration.\n
ONLY_ACTIVE_ARCH = YES\n
endef
export DD_SDK_BASE_XCCONFIG

define DD_SDK_BASE_XCCONFIG_CI
// To ensure no build time warnings slip in without being resolved, treat them as CI build errors:\n
SWIFT_TREAT_WARNINGS_AS_ERRORS = YES\n
\n
// If running on CI. This value is injected to some targets through their `Info.plist`:\n
IS_CI = true\n 
endef
export DD_SDK_BASE_XCCONFIG_CI

define DD_SDK_DATADOG_XCCONFIG_CI
// Datadog secrets provisioning E2E tests data for 'Mobile - Integration' org:\n
E2E_RUM_APPLICATION_ID=${E2E_RUM_APPLICATION_ID}\n
E2E_DATADOG_CLIENT_TOKEN=${E2E_DATADOG_CLIENT_TOKEN}\n
endef
export DD_SDK_DATADOG_XCCONFIG_CI

# Installs tools and dependencies with homebrew.
# Do not call 'brew update' and instead let Bitrise use its own brew bottle mirror.
dependencies:
		@echo "⚙️  Installing dependencies..."
		@brew list swiftlint &>/dev/null || brew install swiftlint
		@brew upgrade carthage
		@carthage bootstrap --platform iOS,tvOS --use-xcframeworks
		@echo $$DD_SDK_BASE_XCCONFIG > xcconfigs/Base.local.xcconfig;
ifeq (${ci}, true)
		@echo $$DD_SDK_BASE_XCCONFIG_CI >> xcconfigs/Base.local.xcconfig;
		@echo $$DD_SDK_DATADOG_XCCONFIG_CI > xcconfigs/Datadog.local.xcconfig;
		@echo $$DD_SDK_TESTING_XCCONFIG_CI > xcconfigs/DatadogSDKTesting.local.xcconfig;
		@brew list gh &>/dev/null || brew install gh
		@rm -rf instrumented-tests/DatadogSDKTesting.xcframework
		@rm -rf instrumented-tests/DatadogSDKTesting.zip
		@rm -rf instrumented-tests/LICENSE
		@gh release download ${DD_SDK_SWIFT_TESTING_VERSION} -D instrumented-tests -R https://github.com/DataDog/dd-sdk-swift-testing -p "DatadogSDKTesting.zip"
		@unzip -q instrumented-tests/DatadogSDKTesting.zip -d instrumented-tests
		@[ -e "instrumented-tests/DatadogSDKTesting.xcframework" ] && echo "DatadogSDKTesting.xcframework - OK" || { echo "DatadogSDKTesting.xcframework - missing"; exit 1; }
endif

xcodeproj-session-replay:
		@echo "⚙️  Generating 'DatadogSessionReplay.xcodeproj'..."
		@cd DatadogSessionReplay/ && swift package generate-xcodeproj
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

# Tests if current branch ships valid a XCFrameworks project.
test-xcframeworks:
		@cd dependency-manager-tests/xcframeworks && $(MAKE)

# Generate RUM data models from rum-events-format JSON Schemas
rum-models-generate:
		@echo "⚙️  Generating RUM models..."
		./tools/rum-models-generator/run.py generate rum
		@echo "OK 👌"

# Verify if RUM data models follow rum-events-format JSON Schemas
rum-models-verify:
		@echo "🧪  Verifying RUM models..."
		./tools/rum-models-generator/run.py verify rum
		@echo "OK 👌"

# Generate Session Replay data models from rum-events-format JSON Schemas
sr-models-generate:
		@echo "⚙️  Generating Session Replay models..."
		./tools/rum-models-generator/run.py generate sr
		@echo "OK 👌"

# Verify if Session Replay data models follow rum-events-format JSON Schemas
sr-models-verify:
		@echo "🧪  Verifying Session Replay models..."
		./tools/rum-models-generator/run.py verify sr
		@echo "OK 👌"

# Generate api-surface files for Datadog and DatadogObjc.
api-surface:
		@cd tools/api-surface/ && swift build --configuration release
		@echo "Generating api-surface-swift"
		./tools/api-surface/.build/x86_64-apple-macosx/release/api-surface workspace --workspace-name Datadog.xcworkspace --scheme "Datadog iOS" --path . > api-surface-swift
		@echo "Generating api-surface-objc"
		./tools/api-surface/.build/x86_64-apple-macosx/release/api-surface workspace --workspace-name Datadog.xcworkspace --scheme "DatadogObjc iOS" --path . > api-surface-objc

# Generate Datadog monitors terraform definition for E2E tests:
e2e-monitors-generate:
		@echo "Deleting previous 'main.tf as it will be soon generated."
		@rm -f tools/nightly-e2e-tests/monitors-gen/main.tf
		@echo "Deleting previous Terraform state and backup as we don't need to track it."
		@rm -f tools/nightly-e2e-tests/monitors-gen/terraform.tfstate
		@rm -f tools/nightly-e2e-tests/monitors-gen/terraform.tfstate.backup
		@echo "⚙️  Generating 'main.tf':"
		@./tools/nightly-e2e-tests/nightly_e2e.py generate-tf --tests-dir ../../Datadog/E2ETests
		@echo "⚠️  Remember to delete all iOS monitors manually from Mobile-Integration org before running 'terraform apply'."

bump:
		@read -p "Enter version number: " version;  \
		echo "// GENERATED FILE: Do not edit directly\n\ninternal let __sdkVersion = \"$$version\"" > Sources/Datadog/Versioning.swift; \
		sed "s/__DATADOG_VERSION__/$$version/g" DatadogSDK.podspec.src > DatadogSDK.podspec; \
		sed "s/__DATADOG_VERSION__/$$version/g" DatadogSDKObjc.podspec.src > DatadogSDKObjc.podspec; \
		sed "s/__DATADOG_VERSION__/$$version/g" DatadogSDKAlamofireExtension.podspec.src > DatadogSDKAlamofireExtension.podspec; \
		sed "s/__DATADOG_VERSION__/$$version/g" DatadogSDKCrashReporting.podspec.src > DatadogSDKCrashReporting.podspec; \
		sed "s/__DATADOG_VERSION__/$$version/g" DatadogSDKSessionReplay.podspec.src > DatadogSDKSessionReplay.podspec; \
		git add . ; \
		git commit -m "Bumped version to $$version"; \
		echo Bumped version to $$version
