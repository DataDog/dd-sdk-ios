.PHONY: clean install test

REPO_ROOT := ../../
include ../../tools/utils/common.mk

ifeq ($(PLATFORM), iOS Simulator)
SCHEME := App iOS
else ifeq ($(PLATFORM), tvOS Simulator)
SCHEME := App tvOS
endif

clean:
	@$(ECHO_SUBTITLE2) "make clean"
	rm -rf SPMProject.xcodeproj App AppTests AppUITests Shared

install:
	@$(ECHO_SUBTITLE2) "make install"
	@$(ECHO_INFO) "Copying source files"
	cp -r ../spm/App App
	cp -r ../spm/AppTests AppTests
	cp -r ../spm/AppUITests AppUITests
	cp -r ../spm/Shared Shared
	@$(ECHO_INFO) "Preparing for CURRENT_GIT_REF='${CURRENT_GIT_REF}' and SWIFT_VERSION = 6.0"
	cp -r ../spm/SPMProject.xcodeproj.src SPMProject.xcodeproj
	sed "s|GIT_REFERENCE|${CURRENT_GIT_REF}|g" ../spm/SPMProject.xcodeproj.src/project.pbxproj | \
		sed "s|GIT_REMOTE|${CURRENT_GIT_REF}|g" | \
		sed "s|SWIFT_VERSION = 5.0|SWIFT_VERSION = 6.0|g"  > SPMProject.xcodeproj/project.pbxproj

test:
	@$(call require_param,OS)
	@$(call require_param,PLATFORM)
	@$(call require_param,DEVICE)
	@$(ECHO_SUBTITLE2) "make test OS='$(OS)' PLATFORM='$(PLATFORM)' DEVICE='$(DEVICE)'"
ifeq ($(SCHEME),)
	@$(ECHO_ERROR) "No SCHEME is defined for PLATFORM='$(PLATFORM)'"
	@exit 1
endif
	@$(ECHO_INFO) "Using SCHEME='$(SCHEME)'"
	set -eo pipefail; \
	xcodebuild -version; \
	xcodebuild -project "SPMProject.xcodeproj" -destination "platform=$(PLATFORM),name=$(DEVICE),OS=$(OS)" -scheme "$(SCHEME)" test | xcbeautify

