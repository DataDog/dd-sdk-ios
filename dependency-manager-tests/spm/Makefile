ifdef ci
		GIT_BRANCH := ${BITRISE_GIT_BRANCH}
else
		GIT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
endif

test:
		@echo "⚙️  Testing SPM for remote branch: '${GIT_BRANCH}'..."
		@sed -i "" "s|branch = *.;|branch = ${GIT_BRANCH};|g" SPMProject.xcodeproj/project.pbxproj
		@xcodebuild -project SPMProject.xcodeproj \
			-scheme "SPMProjectUITests" \
        	   	-destination 'platform=iOS Simulator,name=iPhone 11' \
        	   	test
		@echo "OK 👌"
