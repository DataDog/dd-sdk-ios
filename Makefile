all: env-check repo-setup templates
.PHONY: env-check repo-setup clean templates \
		lint license-check \
		test test-ios test-ios-all test-tvos test-tvos-all \
		ui-test ui-test-all ui-test-podinstall \
		tools-test \
		smoke-test smoke-test-ios smoke-test-ios-all smoke-test-tvos smoke-test-tvos-all \
		spm-build spm-build-ios spm-build-tvos spm-build-visionos spm-build-macos \
		models-generate rum-models-generate sr-models-generate models-verify rum-models-verify sr-models-verify \

REPO_ROOT := $(PWD)
include tools/utils/common.mk

define DD_SDK_TESTING_XCCONFIG_CI
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
endif

endif

# Default ENV for setting up the repo
DEFAULT_ENV := dev

env-check:
	@$(ECHO_TITLE) "make env-check"
	./tools/env-check.sh

repo-setup:
	@:$(eval ENV ?= $(DEFAULT_ENV))
	@$(ECHO_TITLE) "make repo-setup ENV='$(ENV)'"
	./tools/repo-setup/repo-setup.sh --env "$(ENV)"

clean:
	@$(ECHO_TITLE) "make clean"
	./tools/clean.sh

lint:
	@$(ECHO_TITLE) "make lint"
	./tools/lint/run-linter.sh

license-check:
	@$(ECHO_TITLE) "make license-check"
	./tools/license/check-license.sh

# Test env for running iOS tests in local:
DEFAULT_IOS_OS := latest
DEFAULT_IOS_PLATFORM := iOS Simulator
DEFAULT_IOS_DEVICE := iPhone 15 Pro

# Test env for running tvOS tests in local:
DEFAULT_TVOS_OS := latest
DEFAULT_TVOS_PLATFORM := tvOS Simulator
DEFAULT_TVOS_DEVICE := Apple TV

# Run unit tests for specified SCHEME
test:
	@$(call require_param,SCHEME)
	@$(call require_param,OS)
	@$(call require_param,PLATFORM)
	@$(call require_param,DEVICE)
	@$(ECHO_TITLE) "make test SCHEME='$(SCHEME)' OS='$(OS)' PLATFORM='$(PLATFORM)' DEVICE='$(DEVICE)'"
	./tools/test.sh --scheme "$(SCHEME)" --os "$(OS)" --platform "$(PLATFORM)" --device "$(DEVICE)"

# Run unit tests for specified SCHEME using iOS Simulator
test-ios:
	@$(call require_param,SCHEME)
	@:$(eval OS ?= $(DEFAULT_IOS_OS))
	@:$(eval PLATFORM ?= $(DEFAULT_IOS_PLATFORM))
	@:$(eval DEVICE ?= $(DEFAULT_IOS_DEVICE))
	@$(MAKE) test SCHEME="$(SCHEME)" OS="$(OS)" PLATFORM="$(PLATFORM)" DEVICE="$(DEVICE)"

# Run unit tests for all iOS schemes
test-ios-all:
	@$(MAKE) test-ios SCHEME="DatadogCore iOS"
	@$(MAKE) test-ios SCHEME="DatadogInternal iOS"
	@$(MAKE) test-ios SCHEME="DatadogRUM iOS"
	@$(MAKE) test-ios SCHEME="DatadogSessionReplay iOS"
	@$(MAKE) test-ios SCHEME="DatadogLogs iOS"
	@$(MAKE) test-ios SCHEME="DatadogTrace iOS"
	@$(MAKE) test-ios SCHEME="DatadogCrashReporting iOS"
	@$(MAKE) test-ios SCHEME="DatadogWebViewTracking iOS"

# Run unit tests for specified SCHEME using tvOS Simulator
test-tvos:
	@$(call require_param,SCHEME)
	@:$(eval OS ?= $(DEFAULT_TVOS_OS))
	@:$(eval PLATFORM ?= $(DEFAULT_TVOS_PLATFORM))
	@:$(eval DEVICE ?= $(DEFAULT_TVOS_DEVICE))
	@$(MAKE) test SCHEME="$(SCHEME)" OS="$(OS)" PLATFORM="$(PLATFORM)" DEVICE="$(DEVICE)"

# Run unit tests for all tvOS schemes
test-tvos-all:
	@$(MAKE) test-tvos SCHEME="DatadogCore tvOS"
	@$(MAKE) test-tvos SCHEME="DatadogInternal tvOS"
	@$(MAKE) test-tvos SCHEME="DatadogRUM tvOS"
	@$(MAKE) test-tvos SCHEME="DatadogLogs tvOS"
	@$(MAKE) test-tvos SCHEME="DatadogTrace tvOS"
	@$(MAKE) test-tvos SCHEME="DatadogCrashReporting tvOS"

# Run UI tests for specified TEST_PLAN
ui-test:
	@$(call require_param,TEST_PLAN)
	@:$(eval OS ?= $(DEFAULT_IOS_OS))
	@:$(eval PLATFORM ?= $(DEFAULT_IOS_PLATFORM))
	@:$(eval DEVICE ?= $(DEFAULT_IOS_DEVICE))
	@$(ECHO_TITLE) "make ui-test TEST_PLAN='$(TEST_PLAN)' OS='$(OS)' PLATFORM='$(PLATFORM)' DEVICE='$(DEVICE)'"
	./tools/ui-test.sh --test-plan "$(TEST_PLAN)" --os "$(OS)" --platform "$(PLATFORM)" --device "$(DEVICE)"

# Run UI tests for all test plans
ui-test-all:
	@$(MAKE) ui-test TEST_PLAN="Default"
	@$(MAKE) ui-test TEST_PLAN="RUM"
	@$(MAKE) ui-test TEST_PLAN="CrashReporting"
	@$(MAKE) ui-test TEST_PLAN="NetworkInstrumentation"

# Update UI test project with latest SDK
ui-test-podinstall:
	@$(ECHO_TITLE) "make ui-test-podinstall"
	cd IntegrationTests/ && bundle exec pod install

# Run tests for repo tools
tools-test:
	@$(ECHO_TITLE) "make tools-test"
	./tools/tools-test.sh

# Run smoke tests
smoke-test:
	@$(call require_param,TEST_DIRECTORY)
	@$(call require_param,OS)
	@$(call require_param,PLATFORM)
	@$(call require_param,DEVICE)
	@$(ECHO_TITLE) "make smoke-test TEST_DIRECTORY='$(TEST_DIRECTORY)' OS='$(OS)' PLATFORM='$(PLATFORM)' DEVICE='$(DEVICE)'"
	./tools/smoke-test.sh --test-directory "$(TEST_DIRECTORY)" --os "$(OS)" --platform "$(PLATFORM)" --device "$(DEVICE)"

# Run smoke tests for specified TEST_DIRECTORY using iOS Simulator
smoke-test-ios:
	@$(call require_param,TEST_DIRECTORY)
	@:$(eval OS ?= $(DEFAULT_IOS_OS))
	@:$(eval PLATFORM ?= $(DEFAULT_IOS_PLATFORM))
	@:$(eval DEVICE ?= $(DEFAULT_IOS_DEVICE))
	@$(MAKE) smoke-test TEST_DIRECTORY="$(TEST_DIRECTORY)" OS="$(OS)" PLATFORM="$(PLATFORM)" DEVICE="$(DEVICE)"

# Run all smoke tests using iOS Simulator
smoke-test-ios-all:
	# @$(MAKE) smoke-test-ios TEST_DIRECTORY="SmokeTests/spm"
	@$(MAKE) smoke-test-ios TEST_DIRECTORY="SmokeTests/carthage"
	# @$(MAKE) smoke-test-ios TEST_DIRECTORY="SmokeTests/cocoapods"
	# @$(MAKE) smoke-test-ios TEST_DIRECTORY="SmokeTests/xcframeworks"

# Run smoke tests for specified TEST_DIRECTORY using tvOS Simulator
smoke-test-tvos:
	@$(call require_param,TEST_DIRECTORY)
	@:$(eval OS ?= $(DEFAULT_TVOS_OS))
	@:$(eval PLATFORM ?= $(DEFAULT_TVOS_PLATFORM))
	@:$(eval DEVICE ?= $(DEFAULT_TVOS_DEVICE))
	@$(MAKE) smoke-test TEST_DIRECTORY="$(TEST_DIRECTORY)" OS="$(OS)" PLATFORM="$(PLATFORM)" DEVICE="$(DEVICE)"

# Run all smoke tests using tvOS Simulator
smoke-test-tvos-all:
	# @$(MAKE) smoke-test-tvos TEST_DIRECTORY="SmokeTests/spm"
	@$(MAKE) smoke-test-tvos TEST_DIRECTORY="SmokeTests/carthage"
	# @$(MAKE) smoke-test-tvos TEST_DIRECTORY="SmokeTests/cocoapods"
	# @$(MAKE) smoke-test-tvos TEST_DIRECTORY="SmokeTests/xcframeworks"

# Builds SPM package SCHEME for specified DESTINATION
spm-build:
	@$(call require_param,SCHEME)
	@$(call require_param,DESTINATION)
	@$(ECHO_TITLE) "make spm-build SCHEME='$(SCHEME)' DESTINATION='$(DESTINATION)'"
	./tools/spm-build.sh --scheme "$(SCHEME)" --destination "$(DESTINATION)"

# Builds SPM package for iOS
spm-build-ios:
	@$(MAKE) spm-build SCHEME="Datadog-Package" DESTINATION="generic/platform=ios"

# Builds SPM package for tvOS
spm-build-tvos:
	@$(MAKE) spm-build SCHEME="Datadog-Package" DESTINATION="generic/platform=tvOS"

# Builds SPM package for visionOS
spm-build-visionos:
	@$(MAKE) spm-build SCHEME="Datadog-Package" DESTINATION="generic/platform=visionOS"

# Builds SPM package for macOS (and Mac Catalyst)
spm-build-macos:
	# Whole package for Mac Catalyst:
	@$(MAKE) spm-build SCHEME="Datadog-Package" DESTINATION="platform=macOS,variant=Mac Catalyst"
	# Only compatible schemes for macOS:
	@$(MAKE) spm-build DESTINATION="platform=macOS" SCHEME="DatadogCore"
	@$(MAKE) spm-build DESTINATION="platform=macOS" SCHEME="DatadogLogs"
	@$(MAKE) spm-build DESTINATION="platform=macOS" SCHEME="DatadogTrace"
	@$(MAKE) spm-build DESTINATION="platform=macOS" SCHEME="DatadogCrashReporting"

xcodeproj-session-replay:
		@echo "⚙️  Generating 'DatadogSessionReplay.xcodeproj'..."
		@cd DatadogSessionReplay/ && swift package generate-xcodeproj
		@echo "OK 👌"

open-sr-snapshot-tests:
		@echo "⚙️  Opening SRSnapshotTests with DD_TEST_UTILITIES_ENABLED ..."
		@pgrep -q Xcode && killall Xcode && echo "- Xcode killed" || echo "- Xcode not running"
		@sleep 0.5 && echo "- launching" # Sleep, otherwise, if Xcode was running it often fails with "procNotFound: no eligible process with specified descriptor"
		@open --env DD_TEST_UTILITIES_ENABLED ./DatadogSessionReplay/SRSnapshotTests/SRSnapshotTests.xcworkspace

templates:
	@$(ECHO_TITLE) "make templates"
	./tools/xcode-templates/install-xcode-templates.sh

# Generate data models from https://github.com/DataDog/rum-events-format
models-generate:
	@$(call require_param,PRODUCT) # 'rum' or 'sr'
	@$(call require_param,GIT_REF)
	@$(ECHO_TITLE) "make models-generate PRODUCT='$(PRODUCT)' GIT_REF='$(GIT_REF)'"
	./tools/rum-models-generator/run.py generate $(PRODUCT) --git_ref=$(GIT_REF)

# Validate data models against https://github.com/DataDog/rum-events-format
models-verify:
	@$(call require_param,PRODUCT) # 'rum' or 'sr'
	@$(ECHO_TITLE) "make models-verify PRODUCT='$(PRODUCT)'"
	./tools/rum-models-generator/run.py verify $(PRODUCT)

# Generate RUM data models
rum-models-generate:
	@:$(eval GIT_REF ?= master)
	@$(MAKE) models-generate PRODUCT="rum" GIT_REF="$(GIT_REF)"

# Validate RUM data models
rum-models-verify:
	@$(MAKE) models-verify PRODUCT="rum"

# Generate SR data models
sr-models-generate:
	@:$(eval GIT_REF ?= master)
	@$(MAKE) models-generate PRODUCT="sr" GIT_REF="$(GIT_REF)"

# Validate SR data models
sr-models-verify:
	@$(MAKE) models-verify PRODUCT="sr"

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
			--library-name DatadogSessionReplay \
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

e2e-upload:
		./tools/code-sign.sh -- $(MAKE) -C E2ETests
