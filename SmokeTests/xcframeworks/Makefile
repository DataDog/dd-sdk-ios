.PHONY: clean install test

REPO_ROOT := ../../
include ../../tools/utils/common.mk

ifeq ($(PLATFORM), iOS Simulator)
SCHEME := App iOS
BUILD_XCFRAMEWORKS_FLAG := --ios
EXPECTED_XCFRAMEWORKS := DatadogInternal \
						DatadogCore \
						DatadogLogs \
						DatadogTrace \
						DatadogRUM \
						DatadogSessionReplay \
						DatadogObjc \
						DatadogCrashReporting \
						CrashReporter \
						DatadogWebViewTracking \
						OpenTelemetryApi
else ifeq ($(PLATFORM), tvOS Simulator)
SCHEME := App tvOS
BUILD_XCFRAMEWORKS_FLAG := --tvos
EXPECTED_XCFRAMEWORKS := DatadogInternal \
						DatadogCore \
						DatadogLogs \
						DatadogTrace \
						DatadogRUM \
						DatadogObjc \
						DatadogCrashReporting \
						CrashReporter \
						OpenTelemetryApi
endif

clean:
	@$(ECHO_SUBTITLE2) "make clean"
	rm -rf dd-sdk-ios

install:
	@$(call require_param,PLATFORM)
	@$(ECHO_SUBTITLE2) "make install"
	@$(ECHO_INFO) "Preparing for CURRENT_GIT_REF='${CURRENT_GIT_REF}'"
	git clone --depth 1 --branch ${CURRENT_GIT_REF} --single-branch git@github.com:DataDog/dd-sdk-ios.git
ifeq ($(BUILD_XCFRAMEWORKS_FLAG),)
	@$(ECHO_ERROR) "No BUILD_XCFRAMEWORKS_FLAG is defined for PLATFORM='$(PLATFORM)'"
	@exit 1
endif
	cd $(REPO_ROOT) && tools/release/build-xcframeworks.sh \
		--repo-path SmokeTests/xcframeworks/dd-sdk-ios \
		--output-path SmokeTests/xcframeworks/dd-sdk-ios/build/xcframeworks \
		$(BUILD_XCFRAMEWORKS_FLAG)

test:
	@$(call require_param,OS)
	@$(call require_param,PLATFORM)
	@$(call require_param,DEVICE)
	@$(ECHO_SUBTITLE2) "make test OS='$(OS)' PLATFORM='$(PLATFORM)' DEVICE='$(DEVICE)'"
ifeq ($(SCHEME),)
	@$(ECHO_ERROR) "No SCHEME is defined for PLATFORM='$(PLATFORM)'"
	@exit 1
endif
ifeq ($(EXPECTED_XCFRAMEWORKS),)
	@$(ECHO_ERROR) "No EXPECTED_XCFRAMEWORKS is defined for PLATFORM='$(PLATFORM)'"
	@exit 1
endif
	@$(ECHO_INFO) "Using SCHEME='$(SCHEME)'"
	@$(ECHO_INFO) "Using EXPECTED_XCFRAMEWORKS='$(EXPECTED_XCFRAMEWORKS)'"
	@echo "Check XCFrameworks in $(PWD)/dd-sdk-ios/build/xcframeworks/"
	@$(foreach xcf,$(EXPECTED_XCFRAMEWORKS),\
		if [ -d "dd-sdk-ios/build/xcframeworks/$(xcf).xcframework" ]; then \
			$(ECHO_SUCCESS) "$(xcf).xcframework exists"; \
		else \
			$(ECHO_ERROR) "$(xcf).xcframework is missing" && exit 1; \
		fi;)
	set -eo pipefail; \
	xcodebuild -version; \
	xcodebuild -project "XCProject.xcodeproj" -destination "platform=$(PLATFORM),name=$(DEVICE),OS=$(OS)" -scheme "$(SCHEME)" test | xcbeautify
