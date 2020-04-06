ifdef ci
		GIT_BRANCH := ${BITRISE_GIT_BRANCH}
else
		GIT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
endif

test:
		@echo "⚙️  Configuring SPMProject with remote branch: '${GIT_BRANCH}'..."
		@sed -i "" "s|branch = master;|branch = ${GIT_BRANCH};|g" SPMProject.xcodeproj/project.pbxproj
		@rm -rf SPMProject.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
		@echo "OK 👌"
