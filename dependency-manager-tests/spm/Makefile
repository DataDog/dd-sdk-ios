ifdef ci
		GIT_BRANCH := ${BITRISE_GIT_BRANCH}
else
		GIT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
endif

test:
		@echo "⚙️  Configuring SPMProject with remote branch: '${GIT_BRANCH}'..."
		@rm -rf SPMProject.xcodeproj
		@cp -r SPMProject.xcodeproj.src SPMProject.xcodeproj
		@sed "s|REMOTE_GIT_BRANCH|${GIT_BRANCH}|g" SPMProject.xcodeproj.src/project.pbxproj > SPMProject.xcodeproj/project.pbxproj
		@echo "OK 👌"
