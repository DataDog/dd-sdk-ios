ifeq (${ci}, true)
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

create-src-from-xcodeproj:
		@echo "⚙️  Creating 'SPMProject.xcodeproj.src' from SPMProject.xcodeproj"
		rm -rf SPMProject.xcodeproj.src
		cp -r SPMProject.xcodeproj SPMProject.xcodeproj.src
		rm SPMProject.xcodeproj.src/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
		sed "s|\"${GIT_BRANCH}\"|REMOTE_GIT_BRANCH|g" SPMProject.xcodeproj/project.pbxproj > SPMProject.xcodeproj.src/project.pbxproj
		@echo "OK 👌"
