.PHONY: clean install test

REPO_ROOT := ../../
include ../../tools/utils/common.mk

ifeq ($(PLATFORM), iOS Simulator)
SCHEME := App iOS
DD_XCFRAMEWORKS := DatadogInternal \
					DatadogCore \
					DatadogLogs \
					DatadogTrace \
					DatadogRUM \
					DatadogObjc \
					DatadogCrashReporting \
					DatadogSessionReplay \
					DatadogWebViewTracking
THIRD_PARTY_XCFRAMEWORKS := CrashReporter \
							OpenTelemetryApi
DD_XCFRAMEWORK_BUILD_FLAG := --ios
else ifeq ($(PLATFORM), tvOS Simulator)
SCHEME := App tvOS
DD_XCFRAMEWORKS := DatadogInternal \
					DatadogCore \
					DatadogLogs \
					DatadogTrace \
					DatadogRUM \
					DatadogObjc \
					DatadogCrashReporting
THIRD_PARTY_XCFRAMEWORKS := CrashReporter \
							OpenTelemetryApi
DD_XCFRAMEWORK_BUILD_FLAG := --tvos
endif

REPO_CLONE_DIR := $(PWD)/dd-sdk-ios
XCFRAMEWORKS_OUTPUT_DIR := $(REPO_CLONE_DIR)/build

clean:
	@$(ECHO_SUBTITLE2) "make clean"
	rm -rf dd-sdk-ios

install:
	@$(call require_param,PLATFORM)
	@$(ECHO_SUBTITLE2) "make install"
	@$(ECHO_INFO) "Preparing for CURRENT_GIT_REF='${CURRENT_GIT_REF}'"
	@echo "Using REPO_CLONE_DIR = '$(REPO_CLONE_DIR)'"
	@echo "Using XCFRAMEWORKS_OUTPUT_DIR = '$(XCFRAMEWORKS_OUTPUT_DIR)'"

	@$(ECHO_INFO) "Performing a fresh clone of the repository to ensure clean state:"
	git clone --depth 1 --branch ${CURRENT_GIT_REF} --single-branch git@github.com:DataDog/dd-sdk-ios.git $(REPO_CLONE_DIR)
	@$(ECHO_SUCCESS) "Repo cloned to '$(REPO_CLONE_DIR)'"

	@$(ECHO_INFO) "Building Datadog xcframeworks in '$(XCFRAMEWORKS_OUTPUT_DIR)'"
ifeq ($(DD_XCFRAMEWORKS),)
	@$(ECHO_ERROR) "No DD_XCFRAMEWORKS is defined for PLATFORM='$(PLATFORM)'"
	@exit 1
endif
ifeq ($(DD_XCFRAMEWORK_BUILD_FLAG),)
	@$(ECHO_ERROR) "No DD_XCFRAMEWORK_BUILD_FLAG is defined for PLATFORM='$(PLATFORM)'"
	@exit 1
endif
	@cd $(REPO_ROOT) && for xcf in $(DD_XCFRAMEWORKS); do \
		./tools/release/build-dd-xcframework.sh \
			--workspace ./Datadog.xcworkspace \
			--product $$xcf \
			$(DD_XCFRAMEWORK_BUILD_FLAG) \
			--output-dir "$(XCFRAMEWORKS_OUTPUT_DIR)"; \
	done

	@$(ECHO_INFO) "Building third-party xcframeworks in '$(XCFRAMEWORKS_OUTPUT_DIR)'"
	cd $(REPO_ROOT) && ./tools/release/build-3rd-party-xcframeworks.sh --cartfile-path ./Cartfile --output-dir "$(XCFRAMEWORKS_OUTPUT_DIR)"

test:
	@$(call require_param,OS)
	@$(call require_param,PLATFORM)
	@$(call require_param,DEVICE)
	@$(ECHO_SUBTITLE2) "make test OS='$(OS)' PLATFORM='$(PLATFORM)' DEVICE='$(DEVICE)'"
ifeq ($(SCHEME),)
	@$(ECHO_ERROR) "No SCHEME is defined for PLATFORM='$(PLATFORM)'"
	@exit 1
endif
ifeq ($(DD_XCFRAMEWORKS),)
	@$(ECHO_ERROR) "No DD_XCFRAMEWORKS is defined for PLATFORM='$(PLATFORM)'"
	@exit 1
endif
	@$(ECHO_SUCCESS) "Using SCHEME='$(SCHEME)'"
	@$(ECHO_SUCCESS) "Using DD_XCFRAMEWORKS='$(DD_XCFRAMEWORKS)'"
	@echo "Check XCFrameworks in $(PWD)/dd-sdk-ios/build/xcframeworks/"
	@$(foreach xcf,$(DD_XCFRAMEWORKS) $(THIRD_PARTY_XCFRAMEWORKS),\
		if [ -d "dd-sdk-ios/build/xcframeworks/$(xcf).xcframework" ]; then \
			$(ECHO_SUCCESS) "$(xcf).xcframework exists"; \
		else \
			$(ECHO_ERROR) "$(xcf).xcframework is missing" && exit 1; \
		fi;)
	set -eo pipefail; \
	xcodebuild -version; \
	xcodebuild -project "XCProject.xcodeproj" -destination "platform=$(PLATFORM),name=$(DEVICE),OS=$(OS)" -scheme "$(SCHEME)" test | xcbeautify
