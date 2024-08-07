.PHONY: clean install test create-src-from-xcodeproj

REPO_ROOT := ../../
include ../../tools/utils/common.mk

ifeq ($(PLATFORM), iOS Simulator)
SCHEME := App iOS
CARTHAGE_PLATFORM := iOS
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
CARTHAGE_PLATFORM := tvOS
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
	rm -rf Carthage
	rm -f Cartfile.resolved
	rm -f Cartfile

install:
	@$(ECHO_SUBTITLE2) "make install"
	@$(ECHO_INFO) "Preparing for CURRENT_GIT_REF='${CURRENT_GIT_REF}'"
	sed "s|GIT_REFERENCE|${CURRENT_GIT_REF}|g" Cartfile.src > Cartfile
ifeq ($(CARTHAGE_PLATFORM),)
	@$(ECHO_ERROR) "No CARTHAGE_PLATFORM is defined for PLATFORM='$(PLATFORM)'"
	@exit 1
endif
	@$(ECHO_INFO) "Using CARTHAGE_PLATFORM='$(CARTHAGE_PLATFORM)'"
	REPO_ROOT=$(REPO_ROOT) $(REPO_ROOT)/tools/carthage-shim.sh update --platform $(CARTHAGE_PLATFORM) --use-xcframeworks

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
	@echo "Check XCFrameworks in $(PWD)/Carthage/Build/"
	@$(foreach xcf,$(EXPECTED_XCFRAMEWORKS),\
		if [ -d "Carthage/Build/$(xcf).xcframework" ]; then \
			$(ECHO_SUCCESS) "$(xcf).xcframework exists"; \
		else \
			$(ECHO_ERROR) "$(xcf).xcframework is missing" && exit 1; \
		fi;)
	set -eo pipefail; \
	xcodebuild -version; \
	xcodebuild -project "CTProject.xcodeproj" -destination "platform=$(PLATFORM),name=$(DEVICE),OS=$(OS)" -scheme "$(SCHEME)" test | xcbeautify
