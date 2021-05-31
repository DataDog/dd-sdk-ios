GIT_REFERENCE := $(shell git rev-parse --abbrev-ref HEAD)
ifneq (${BITRISE_GIT_BRANCH},)
	GIT_REFERENCE := ${BITRISE_GIT_BRANCH}
endif
ifneq (${BITRISE_GIT_TAG},)
	GIT_REFERENCE := ${BITRISE_GIT_TAG}
endif

test:
		@echo "⚙️  Configuring SPMProject with remote branch: '${GIT_REFERENCE}'..."
		@rm -rf SPMProject.xcodeproj
		@cp -r SPMProject.xcodeproj.src SPMProject.xcodeproj
		@sed "s|REMOTE_GIT_REFERENCE|${GIT_REFERENCE}|g" SPMProject.xcodeproj.src/project.pbxproj > SPMProject.xcodeproj/project.pbxproj
		@echo "OK 👌"

create-src-from-xcodeproj:
		@echo "⚙️  Creating 'SPMProject.xcodeproj.src' from SPMProject.xcodeproj"
		rm -rf SPMProject.xcodeproj.src
		cp -r SPMProject.xcodeproj SPMProject.xcodeproj.src
		rm SPMProject.xcodeproj.src/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
		sed "s|\"${GIT_REFERENCE}\"|REMOTE_GIT_REFERENCE|g" SPMProject.xcodeproj/project.pbxproj > SPMProject.xcodeproj.src/project.pbxproj
		@echo "OK 👌"
