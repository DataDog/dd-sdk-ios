ifdef ci
		GIT_BRANCH := ${BITRISE_GIT_BRANCH}
else
		GIT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
endif

test:
		@echo "⚙️  Configuring SPMProject with remote branch: '${GIT_BRANCH}'..."
		@rm -rf SPMProject.xcodeproj/project.pbxproj
		@rm -rf SPMProject.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
		@sed "s|REMOTE_GIT_BRANCH|${GIT_BRANCH}|g" project.pbxproj.src > SPMProject.xcodeproj/project.pbxproj
		@echo "OK 👌"
