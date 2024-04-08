all: dependencies templates

# The release version of `dd-sdk-swift-testing` to use for tests instrumentation.
DD_SDK_SWIFT_TESTING_VERSION = 2.3.2
DD_DISABLE_TEST_INSTRUMENTING = false

define DD_SDK_TESTING_XCCONFIG_CI
DD_SDK_TESTING_PATH=$$(DD_SDK_TESTING_OVERRIDE_PATH:default=$$(SRCROOT)/../instrumented-tests/)\n
FRAMEWORK_SEARCH_PATHS[sdk=iphonesimulator*]=$$(inherited) $$(DD_SDK_TESTING_PATH)/DatadogSDKTesting.xcframework/ios-arm64_x86_64-simulator/\n
LD_RUNPATH_SEARCH_PATHS[sdk=iphonesimulator*]=$$(inherited) $$(DD_SDK_TESTING_PATH)/DatadogSDKTesting.xcframework/ios-arm64_x86_64-simulator/\n
FRAMEWORK_SEARCH_PATHS[sdk=appletvsimulator*]=$$(inherited) $$(DD_SDK_TESTING_PATH)/DatadogSDKTesting.xcframework/tvos-arm64_x86_64-simulator/\n
LD_RUNPATH_SEARCH_PATHS[sdk=appletvsimulator*]=$$(inherited) $$(DD_SDK_TESTING_PATH)/DatadogSDKTesting.xcframework/tvos-arm64_x86_64-simulator/\n
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
\n
// Adjust the deployment target for all projects and targets in `dd-sdk-ios` (including Datadog.xcworkspace and IntegrationTests.xcworkspace).\n
// This is to fix Xcode 15 warnings and errors like:\n
// - 'The iOS Simulator deployment target 'IPHONEOS_DEPLOYMENT_TARGET' is set to 11.0, but the range of supported deployment target versions is 12.0 to 17.0.99.'.\n
// - 'Compiling for iOS 11.0, but module 'SRFixtures' has a minimum deployment target of iOS 12.0'\n
IPHONEOS_DEPLOYMENT_TARGET=12.0\n
endef
export DD_SDK_BASE_XCCONFIG

define DD_SDK_BASE_XCCONFIG_CI
// To ensure no build time warnings slip in without being resolved, treat them as CI build errors:\n
SWIFT_TREAT_WARNINGS_AS_ERRORS = YES\n
\n
// If running on CI. This value is injected to some targets through their `Info.plist`:\n
IS_CI = true\n
\n
// Use iOS 11 deployment target on CI as long as we use Xcode 14.x for integration\n
IPHONEOS_DEPLOYMENT_TARGET=11.0\n
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
		@bundle install
		@brew list swiftlint &>/dev/null || brew install swiftlint
		@brew upgrade carthage
		@carthage bootstrap --platform iOS,tvOS --use-xcframeworks
		@echo $$DD_SDK_BASE_XCCONFIG > xcconfigs/Base.local.xcconfig;
		@brew list gh &>/dev/null || brew install gh
ifeq (${ci}, true)
		@echo $$DD_SDK_BASE_XCCONFIG_CI >> xcconfigs/Base.local.xcconfig;
		@echo $$DD_SDK_DATADOG_XCCONFIG_CI > xcconfigs/Datadog.local.xcconfig;
ifndef DD_DISABLE_TEST_INSTRUMENTING
		@echo $$DD_SDK_TESTING_XCCONFIG_CI > xcconfigs/DatadogSDKTesting.local.xcconfig;
		@rm -rf instrumented-tests/DatadogSDKTesting.xcframework
		@rm -rf instrumented-tests/DatadogSDKTesting.zip
		@rm -rf instrumented-tests/LICENSE
		@gh release download ${DD_SDK_SWIFT_TESTING_VERSION} -D instrumented-tests -R https://github.com/DataDog/dd-sdk-swift-testing -p "DatadogSDKTesting.zip"
		@unzip -q instrumented-tests/DatadogSDKTesting.zip -d instrumented-tests
		@[ -e "instrumented-tests/DatadogSDKTesting.xcframework" ] && echo "DatadogSDKTesting.xcframework - OK" || { echo "DatadogSDKTesting.xcframework - missing"; exit 1; }
endif

endif

# Prepare project on GitLab CI (this will replace `make dependencies` once we're fully on GitLab).
dependencies-gitlab:
		@echo "📝  Source xcconfigs..."
		@echo $$DD_SDK_BASE_XCCONFIG > xcconfigs/Base.local.xcconfig;
		@echo $$DD_SDK_BASE_XCCONFIG_CI >> xcconfigs/Base.local.xcconfig;
		# We use Xcode 15 on GitLab, so overwrite deployment target in all projects to avoid build errors:
		@echo "IPHONEOS_DEPLOYMENT_TARGET=12.0\n" >> xcconfigs/Base.local.xcconfig;
		@echo "⚙️  Carthage bootstrap..."
		@carthage bootstrap --platform iOS,tvOS --use-xcframeworks

xcodeproj-session-replay:
		@echo "⚙️  Generating 'DatadogSessionReplay.xcodeproj'..."
		@cd DatadogSessionReplay/ && swift package generate-xcodeproj
		@echo "OK 👌"

prepare-integration-tests:
		@echo "⚙️  Prepare Integration Tests ..."
		@cd IntegrationTests/ && pod install
		@echo "OK 👌"

open-sr-snapshot-tests:
		@echo "⚙️  Opening SRSnapshotTests with DD_TEST_UTILITIES_ENABLED ..."
		@pgrep -q Xcode && killall Xcode && echo "- Xcode killed" || echo "- Xcode not running"
		@sleep 0.5 && echo "- launching" # Sleep, otherwise, if Xcode was running it often fails with "procNotFound: no eligible process with specified descriptor"
		@open --env DD_TEST_UTILITIES_ENABLED ./DatadogSessionReplay/SRSnapshotTests/SRSnapshotTests.xcworkspace

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
#  - run with `git_ref=<commit hash>` argument to generate models for given schema commit or branch name (default is 'master').
rum-models-generate:
		@echo "⚙️  Generating RUM models..."
		./tools/rum-models-generator/run.py generate rum --git_ref=$(if $(git_ref),$(git_ref),master)
		@echo "OK 👌"

# Verify if RUM data models follow rum-events-format JSON Schemas
rum-models-verify:
		@echo "🧪  Verifying RUM models..."
		./tools/rum-models-generator/run.py verify rum
		@echo "OK 👌"

# Generate Session Replay data models from rum-events-format JSON Schemas
#  - run with `git_ref=<commit hash>` argument to generate models for given schema commit or branch name (default is 'master').
sr-models-generate:
		@echo "⚙️  Generating Session Replay models..."
		./tools/rum-models-generator/run.py generate sr --git_ref=$(if $(git_ref),$(git_ref),master)
		@echo "OK 👌"

# Verify if Session Replay data models follow rum-events-format JSON Schemas
sr-models-verify:
		@echo "🧪  Verifying Session Replay models..."
		./tools/rum-models-generator/run.py verify sr
		@echo "OK 👌"

sr-push-snapshots:
		@echo "🎬 ↗️  Pushing SR snapshots to remote repo..."
		@cd tools/sr-snapshots && swift run sr-snapshots push \
			--local-folder ../../DatadogSessionReplay/SRSnapshotTests/SRSnapshotTests/_snapshots_ \
			--remote-folder ../../../dd-mobile-session-replay-snapshots \
			--remote-branch "main"

sr-pull-snapshots:
		@echo "🎬 ↙️  Pulling SR snapshots from remote repo..."
		@cd tools/sr-snapshots && swift run sr-snapshots pull \
			--local-folder ../../DatadogSessionReplay/SRSnapshotTests/SRSnapshotTests/_snapshots_ \
			--remote-folder ../../../dd-mobile-session-replay-snapshots \
			--remote-branch "main"

# Generate api-surface files for Datadog and DatadogObjc.
api-surface:
		@echo "Generating api-surface-swift"
		@cd tools/api-surface && \
			swift run api-surface spm \
			--path ../../ \
			--library-name DatadogCore \
			--library-name DatadogLogs \
			--library-name DatadogTrace \
			--library-name DatadogRUM \
			--library-name DatadogCrashReporting \
			--library-name DatadogWebViewTracking \
			> ../../api-surface-swift && \
			cd -

		@echo "Generating api-surface-objc"
		@cd tools/api-surface && \
			swift run api-surface spm \
			--path ../../ \
			--library-name DatadogObjc \
			> ../../api-surface-objc && \
			cd -

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
		echo "// GENERATED FILE: Do not edit directly\n\ninternal let __sdkVersion = \"$$version\"" > DatadogCore/Sources/Versioning.swift; \
		./tools/podspec_bump_version.sh $$version; \
		git add . ; \
		git commit -m "Bumped version to $$version"; \
		echo Bumped version to $$version
