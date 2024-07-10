.PHONY: clean install test create-src-from-xcodeproj

REPO_ROOT := ../../
include ../../tools/utils/common.mk

ifeq ($(PLATFORM), iOS Simulator)
SCHEME := App iOS
else ifeq ($(PLATFORM), tvOS Simulator)
SCHEME := App tvOS
endif

clean:
	@$(ECHO_SUBTITLE2) "make clean"
	rm -rf SPMProject.xcodeproj

install:
	@$(ECHO_SUBTITLE2) "make install"
	@$(ECHO_INFO) "Preparing for CURRENT_GIT_REF='${CURRENT_GIT_REF}'"
	cp -r SPMProject.xcodeproj.src SPMProject.xcodeproj
	sed "s|GIT_REFERENCE|${CURRENT_GIT_REF}|g" SPMProject.xcodeproj.src/project.pbxproj | \
		sed "s|GIT_REMOTE|${CURRENT_GIT_REF}|g" > SPMProject.xcodeproj/project.pbxproj

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

# Helper to apply any changes made to 'SPMProject.xcodeproj' back to 'SPMProject.xcodeproj.src'
create-src-from-xcodeproj:
	@$(ECHO_SUBTITLE2) "make create-src-from-xcodeproj"
	@echo "Creating 'SPMProject.xcodeproj.src' template from 'SPMProject.xcodeproj'"
	rm -rf SPMProject.xcodeproj.src
	cp -r SPMProject.xcodeproj SPMProject.xcodeproj.src
	rm SPMProject.xcodeproj.src/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
	sed "s|${CURRENT_GIT_REF}|GIT_REFERENCE|g" SPMProject.xcodeproj/project.pbxproj > SPMProject.xcodeproj.src/project.pbxproj
	@$(ECHO_SUCCESS) "'SPMProject.xcodeproj.src' template was updated from 'SPMProject.xcodeproj'"
