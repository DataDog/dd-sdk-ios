all: env-check repo-setup dependencies templates
.PHONY: env-check repo-setup dependencies clean templates \
		lint license-check \
		test test-ios test-ios-all test-tvos test-tvos-all \
		ui-test ui-test-all ui-test-podinstall \
		sr-snapshot-test sr-snapshots-pull sr-snapshots-push sr-snapshot-tests-open \
		tools-test \
		smoke-test smoke-test-ios smoke-test-ios-all smoke-test-tvos smoke-test-tvos-all \
		spm-build spm-build-ios spm-build-tvos spm-build-visionos spm-build-macos spm-build-watchos \
		e2e-upload \
		benchmark-build benchmark-upload \
		models-generate rum-models-generate sr-models-generate models-verify rum-models-verify sr-models-verify \
		dogfood-shopist dogfood-datadog-app \
		release-build release-validate release-publish-github \
		release-publish-podspec release-publish-internal-podspecs release-publish-dependent-podspecs release-publish-legacy-podspecs \
		set-ci-secret

REPO_ROOT := $(PWD)
include tools/utils/common.mk

# Default ENV for setting up the repo
DEFAULT_ENV := dev

env-check:
	@$(ECHO_TITLE) "make env-check"
	./tools/env-check.sh

repo-setup:
	@:$(eval ENV ?= $(DEFAULT_ENV))
	@$(ECHO_TITLE) "make repo-setup ENV='$(ENV)'"
	./tools/repo-setup/repo-setup.sh --env "$(ENV)"

dependencies:
	@$(ECHO_TITLE) "make dependencies"
	./tools/repo-setup/carthage-bootstrap.sh

clean:
	@$(ECHO_TITLE) "make clean"
	./tools/clean.sh --derived-data --pods --xcconfigs

clean-carthage:
	@$(ECHO_TITLE) "make clean-carthage"
	./tools/clean.sh --carthage

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

# Test env for running SR snapshot tests in local:
DEFAULT_SR_SNAPSHOT_TESTS_OS := 17.5
DEFAULT_SR_SNAPSHOT_TESTS_PLATFORM := iOS Simulator
DEFAULT_SR_SNAPSHOT_TESTS_DEVICE := iPhone 15

# Default location for deploying artifacts
DEFAULT_ARTIFACTS_PATH := artifacts

# Whether Test Visibility product is enabled by default
DEFAULT_USE_TEST_VISIBILITY := 0

SKIP_OBJC_TYPES ?= TelemetryUsageEvent

# Run unit tests for specified SCHEME
test:
	@$(call require_param,SCHEME)
	@$(call require_param,OS)
	@$(call require_param,PLATFORM)
	@$(call require_param,DEVICE)
	@:$(eval USE_TEST_VISIBILITY ?= $(DEFAULT_USE_TEST_VISIBILITY))
	@$(ECHO_TITLE) "make test SCHEME='$(SCHEME)' OS='$(OS)' PLATFORM='$(PLATFORM)' DEVICE='$(DEVICE)' USE_TEST_VISIBILITY='$(USE_TEST_VISIBILITY)'"
	USE_TEST_VISIBILITY=$(USE_TEST_VISIBILITY) ./tools/test.sh --scheme "$(SCHEME)" --os "$(OS)" --platform "$(PLATFORM)" --device "$(DEVICE)"

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
	@$(MAKE) test-ios SCHEME="DatadogProfiling iOS"
	@$(MAKE) test-ios SCHEME="DatadogIntegrationTests iOS"

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
	@$(MAKE) test-tvos SCHEME="DatadogProfiling tvOS"
	@$(MAKE) test-tvos SCHEME="DatadogIntegrationTests tvOS"

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
	@$(MAKE) smoke-test-ios TEST_DIRECTORY="SmokeTests/spm"
	@$(MAKE) smoke-test-ios TEST_DIRECTORY="SmokeTests/carthage"
	@$(MAKE) smoke-test-ios TEST_DIRECTORY="SmokeTests/cocoapods"
	@$(MAKE) smoke-test-ios TEST_DIRECTORY="SmokeTests/xcframeworks"

# Run smoke tests for specified TEST_DIRECTORY using tvOS Simulator
smoke-test-tvos:
	@$(call require_param,TEST_DIRECTORY)
	@:$(eval OS ?= $(DEFAULT_TVOS_OS))
	@:$(eval PLATFORM ?= $(DEFAULT_TVOS_PLATFORM))
	@:$(eval DEVICE ?= $(DEFAULT_TVOS_DEVICE))
	@$(MAKE) smoke-test TEST_DIRECTORY="$(TEST_DIRECTORY)" OS="$(OS)" PLATFORM="$(PLATFORM)" DEVICE="$(DEVICE)"

# Run all smoke tests using tvOS Simulator
smoke-test-tvos-all:
	@$(MAKE) smoke-test-tvos TEST_DIRECTORY="SmokeTests/spm"
	@$(MAKE) smoke-test-tvos TEST_DIRECTORY="SmokeTests/carthage"
	@$(MAKE) smoke-test-tvos TEST_DIRECTORY="SmokeTests/cocoapods"
	@$(MAKE) smoke-test-tvos TEST_DIRECTORY="SmokeTests/xcframeworks"

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

# Builds SPM package for watchOS
spm-build-watchos:
	# Build only compatible schemes for watchOS:
	@$(MAKE) spm-build DESTINATION="generic/platform=watchOS" SCHEME="DatadogCore"
	@$(MAKE) spm-build DESTINATION="generic/platform=watchOS" SCHEME="DatadogLogs"
	@$(MAKE) spm-build DESTINATION="generic/platform=watchOS" SCHEME="DatadogTrace"

# Builds SPM package for macOS (and Mac Catalyst)
spm-build-macos:
	# Whole package for Mac Catalyst:
	@$(MAKE) spm-build SCHEME="Datadog-Package" DESTINATION="platform=macOS,variant=Mac Catalyst"
	# Only compatible schemes for macOS:
	@$(MAKE) spm-build DESTINATION="platform=macOS" SCHEME="DatadogCore"
	@$(MAKE) spm-build DESTINATION="platform=macOS" SCHEME="DatadogLogs"
	@$(MAKE) spm-build DESTINATION="platform=macOS" SCHEME="DatadogTrace"
	@$(MAKE) spm-build DESTINATION="platform=macOS" SCHEME="DatadogCrashReporting"

# Builds a new version of the E2E app and publishes it to synthetics.
e2e-upload:
	@$(call require_param,ARTIFACTS_PATH)
	@:$(eval DRY_RUN ?= 1)
	@$(ECHO_TITLE) "make e2e-upload ARTIFACTS_PATH='$(ARTIFACTS_PATH)' DRY_RUN='$(DRY_RUN)'"
	DRY_RUN=$(DRY_RUN) ./tools/e2e-build-upload.sh --artifacts-path "$(ARTIFACTS_PATH)"

# Builds the Benchmark app.
benchmark-build:
	@$(ECHO_TITLE) "make benchmark-build"
	@$(MAKE) -C BenchmarkTests build

# Builds a new version of the Benchmark app and publishes it to synthetics.
benchmark-upload:
	@$(call require_param,ARTIFACTS_PATH)
	@:$(eval DRY_RUN ?= 1)
	@$(ECHO_TITLE) "make benchmark-upload ARTIFACTS_PATH='$(ARTIFACTS_PATH)' DRY_RUN='$(DRY_RUN)'"
	DRY_RUN=$(DRY_RUN) ./tools/benchmark-build-upload.sh --artifacts-path "$(ARTIFACTS_PATH)"

# Opens `BenchmarkTests` project with passing required ENV variables
benchmark-tests-open:
	@$(ECHO_TITLE) "make benchmark-tests-open"
	@$(MAKE) -C BenchmarkTests open

xcodeproj-session-replay:
		@echo "⚙️  Generating 'DatadogSessionReplay.xcodeproj'..."
		@cd DatadogSessionReplay/ && swift package generate-xcodeproj
		@echo "OK 👌"

templates:
	@$(ECHO_TITLE) "make templates"
	./tools/xcode-templates/install-xcode-templates.sh

# Generate data models from https://github.com/DataDog/rum-events-format
models-generate:
	@$(call require_param,PRODUCT) # 'rum' or 'sr'
	@$(call require_param,GIT_REF)
	@$(ECHO_TITLE) "make models-generate PRODUCT='$(PRODUCT)' GIT_REF='$(GIT_REF)'"
	./tools/rum-models-generator/run.py generate $(PRODUCT) --git_ref=$(GIT_REF) --skip_objc $(SKIP_OBJC_TYPES)
# Validate data models against https://github.com/DataDog/rum-events-format
models-verify:
	@$(call require_param,PRODUCT) # 'rum' or 'sr'
	@$(ECHO_TITLE) "make models-verify PRODUCT='$(PRODUCT)'"
	./tools/rum-models-generator/run.py verify $(PRODUCT) --skip_objc $(SKIP_OBJC_TYPES)

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

# Pushes current SR snapshots to snapshots repo
sr-snapshots-push:
	@$(ECHO_TITLE) "make sr-snapshots-push"
	./tools/sr-snapshot-test.sh --push

# Pulls SR snapshots from snapshots repo
sr-snapshots-pull:
	@$(ECHO_TITLE) "make sr-snapshots-pull"
	./tools/sr-snapshot-test.sh --pull

# Run Session Replay snapshot tests
sr-snapshot-test:
	@:$(eval OS ?= $(DEFAULT_SR_SNAPSHOT_TESTS_OS))
	@:$(eval PLATFORM ?= $(DEFAULT_SR_SNAPSHOT_TESTS_PLATFORM))
	@:$(eval DEVICE ?= $(DEFAULT_SR_SNAPSHOT_TESTS_DEVICE))
	@:$(eval ARTIFACTS_PATH ?= $(DEFAULT_ARTIFACTS_PATH))
	@$(ECHO_TITLE) "make sr-snapshot-test OS='$(OS)' PLATFORM='$(PLATFORM)' DEVICE='$(DEVICE)' ARTIFACTS_PATH='$(ARTIFACTS_PATH)'"
	./tools/sr-snapshot-test.sh \
		--test --os "$(OS)" --device "$(DEVICE)" --platform "$(PLATFORM)" --artifacts-path "$(ARTIFACTS_PATH)"

# Opens `SRSnapshotTests` project with passing required ENV variables
sr-snapshot-tests-open:
	@$(ECHO_TITLE) "make sr-snapshot-tests-open"
	./tools/sr-snapshot-test.sh --open-project

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
			--library-name DatadogProfiling \
			> ../../api-surface-swift && \
			cd -

		@echo "Generating api-surface-objc"
		@cd tools/api-surface && \
			swift run api-surface spm \
			--path ../../ \
			--library-name DatadogObjc \
			> ../../api-surface-objc && \
			cd -

# Creates dogfooding PR in shopist-ios
dogfood-shopist:
	@:$(eval DRY_RUN ?= 1)
	@$(ECHO_TITLE) "make dogfood-shopist DRY_RUN='$(DRY_RUN)'"
	DRY_RUN=$(DRY_RUN) ./tools/dogfooding/dogfood.sh --shopist

# Creates dogfooding PR in datadog-ios
dogfood-datadog-app:
	@:$(eval DRY_RUN ?= 1)
	@$(ECHO_TITLE) "make dogfood-datadog-app DRY_RUN='$(DRY_RUN)'"
	DRY_RUN=$(DRY_RUN) ./tools/dogfooding/dogfood.sh --datadog-app

# Builds release artifacts for given tag
release-build:
	@$(call require_param,GIT_TAG)
	@$(call require_param,ARTIFACTS_PATH)
	@$(ECHO_TITLE) "make release-build GIT_TAG='$(GIT_TAG)' ARTIFACTS_PATH='$(ARTIFACTS_PATH)'"
	./tools/release/build.sh --tag "$(GIT_TAG)" --artifacts-path "$(ARTIFACTS_PATH)"

# Validate release artifacts for given tag
release-validate:
	@$(call require_param,GIT_TAG)
	@$(call require_param,ARTIFACTS_PATH)
	@$(ECHO_TITLE) "make release-validate GIT_TAG='$(GIT_TAG)' ARTIFACTS_PATH='$(ARTIFACTS_PATH)'"
	./tools/release/validate-version.sh --artifacts-path "$(ARTIFACTS_PATH)" --tag "$(GIT_TAG)"
	./tools/release/validate-xcframeworks.sh --artifacts-path "$(ARTIFACTS_PATH)"

# Publish GitHub asset to GH release
release-publish-github:
	@$(call require_param,GIT_TAG)
	@$(call require_param,ARTIFACTS_PATH)
	@:$(eval DRY_RUN ?= 1)
	@:$(eval OVERWRITE_EXISTING ?= 0)
	@$(ECHO_TITLE) "make release-publish-github GIT_TAG='$(GIT_TAG)' ARTIFACTS_PATH='$(ARTIFACTS_PATH)' DRY_RUN='$(DRY_RUN)' OVERWRITE_EXISTING='$(OVERWRITE_EXISTING)'"
	DRY_RUN=$(DRY_RUN) OVERWRITE_EXISTING=$(OVERWRITE_EXISTING) ./tools/release/publish-github.sh \
		 --artifacts-path "$(ARTIFACTS_PATH)" \
		 --tag "$(GIT_TAG)"

# Publish Cocoapods podspec to trunk
release-publish-podspec:
	@$(call require_param,PODSPEC_NAME)
	@$(call require_param,ARTIFACTS_PATH)
	@:$(eval DRY_RUN ?= 1)
	@$(ECHO_TITLE) "make release-publish-podspec PODSPEC_NAME='$(PODSPEC_NAME)' ARTIFACTS_PATH='$(ARTIFACTS_PATH)' DRY_RUN='$(DRY_RUN)'"
	DRY_RUN=$(DRY_RUN) ./tools/release/publish-podspec.sh \
		 --artifacts-path "$(ARTIFACTS_PATH)" \
		 --podspec-name "$(PODSPEC_NAME)"

# Publish DatadogInternal podspec
release-publish-internal-podspecs:
	@$(MAKE) release-publish-podspec PODSPEC_NAME="DatadogInternal.podspec"

# Publish podspecs that depend on DatadogInternal
release-publish-dependent-podspecs:
	@$(MAKE) release-publish-podspec PODSPEC_NAME="DatadogCore.podspec"
	@$(MAKE) release-publish-podspec PODSPEC_NAME="DatadogLogs.podspec"
	@$(MAKE) release-publish-podspec PODSPEC_NAME="DatadogTrace.podspec"
	@$(MAKE) release-publish-podspec PODSPEC_NAME="DatadogRUM.podspec"
	@$(MAKE) release-publish-podspec PODSPEC_NAME="DatadogSessionReplay.podspec"
	@$(MAKE) release-publish-podspec PODSPEC_NAME="DatadogCrashReporting.podspec"
	@$(MAKE) release-publish-podspec PODSPEC_NAME="DatadogWebViewTracking.podspec"
	@$(MAKE) release-publish-podspec PODSPEC_NAME="DatadogProfiling.podspec"

# Publish legacy podspecs
release-publish-legacy-podspecs:
	@$(MAKE) release-publish-podspec PODSPEC_NAME="DatadogObjc.podspec"
	@$(MAKE) release-publish-podspec PODSPEC_NAME="DatadogAlamofireExtension.podspec"

# Set ot update CI secrets
set-ci-secret:
	@$(ECHO_TITLE) "make set-ci-secret"
	@./tools/secrets/set-secret.sh

bump:
	@read -p "Enter version number: " version;  \
	echo "// GENERATED FILE: Do not edit directly\n\ninternal let __sdkVersion = \"$$version\"" > DatadogCore/Sources/Versioning.swift; \
	./tools/podspec_bump_version.sh $$version; \
	git add . ; \
	git commit -m "Bumped version to $$version"; \
	echo Bumped version to $$version
