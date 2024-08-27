.PHONY: clean archive export upload

REPO_ROOT := ../
include ../tools/utils/common.mk

BUILD_DIR := .build
ARCHIVE_PATH := $(BUILD_DIR)/Runner.xcarchive
IPA_PATH := $(ARTIFACTS_PATH)/Runner.ipa

clean:
	@$(ECHO_SUBTITLE2) "make clean"
	rm -rf "$(BUILD_DIR)"
ifdef ARTIFACTS_PATH
	rm -rf "$(IPA_PATH)"
endif

build:
	@$(ECHO_SUBTITLE2) "make build"
	set -eo pipefail; \
	OTEL_SWIFT=1 xcodebuild \
		-project BenchmarkTests.xcodeproj \
		-scheme Runner \
		-sdk iphonesimulator \
		-configuration Release \
		-destination generic/platform=iOS\ Simulator \
	| xcbeautify
	@$(ECHO_SUCCESS) "BenchmarkTests compiles"

archive:
	@:$(eval VERSION ?= $(CURRENT_GIT_COMMIT_SHORT))
	@$(ECHO_SUBTITLE2) "make archive VERSION='$(VERSION)'"
	@xcrun agvtool new-version "$(VERSION)"
	set -eo pipefail; \
	BENCHMARK=1 OTEL_SWIFT=1 xcodebuild \
		-project BenchmarkTests.xcodeproj \
		-scheme Runner \
		-sdk iphoneos \
		-configuration Synthetics \
		-destination generic/platform=iOS \
		-archivePath $(ARCHIVE_PATH) \
		archive | xcbeautify
	@$(ECHO_SUCCESS) "Archive ready in '$(ARCHIVE_PATH)'"

export:
	@$(call require_param,ARTIFACTS_PATH)
	@:$(eval VERSION ?= $(CURRENT_GIT_COMMIT_SHORT))
	@$(ECHO_SUBTITLE2) "make export VERSION='$(VERSION)' ARTIFACTS_PATH='$(ARTIFACTS_PATH)'"
	set -o pipefaill; \
	xcodebuild -exportArchive \
		-archivePath $(ARCHIVE_PATH)  \
		-exportOptionsPlist exportOptions.plist \
		-exportPath $(BUILD_DIR) \
		| xcbeautify
	mkdir -p "$(ARTIFACTS_PATH)"
	cp -v "$(BUILD_DIR)/Runner.ipa" "$(IPA_PATH)"
	@$(ECHO_SUCCESS) "IPA exported to '$(IPA_PATH)'"

upload:
	@$(call require_param,ARTIFACTS_PATH)
	@$(call require_param,DATADOG_API_KEY)
	@$(call require_param,DATADOG_APP_KEY)
	@$(call require_param,S8S_APPLICATION_ID)
	@:$(eval VERSION ?= $(CURRENT_GIT_COMMIT_SHORT))
	@$(ECHO_SUBTITLE2) "make upload VERSION='$(VERSION)' ARTIFACTS_PATH='$(ARTIFACTS_PATH)'"
	datadog-ci synthetics upload-application \
		--mobileApp "$(IPA_PATH)" \
		--mobileApplicationId "${S8S_APPLICATION_ID}" \
		--versionName "$(VERSION)" \
		--latest

open:
	@$(ECHO_SUBTITLE2) "make open"
	@open --env DD_BENCHMARK --env OTEL_SWIFT --new BenchmarkTests.xcodeproj
