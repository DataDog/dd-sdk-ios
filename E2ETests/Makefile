all: archive upload

dependencies:
	@echo "⚙️  Installing datadog-ci..."
	@npm install -g @datadog/datadog-ci
	@echo "⚙️  Installing xcbeautify..."
	@brew install xcbeautify

archive:
	xcrun agvtool new-version "$(git rev-parse --short HEAD)"
	
	set -o pipefail && xcodebuild \
		-project E2ETests.xcodeproj \
		-scheme Runner \
		-sdk iphoneos \
		-configuration Synthetics \
		-destination generic/platform=iOS \
		-archivePath .build/Runner.xcarchive \
	archive | xcbeautify

	set -o pipefail && xcodebuild -exportArchive \
		-archivePath .build/Runner.xcarchive  \
		-exportOptionsPlist exportOptions.plist \
		-exportPath .build \
	| xcbeautify

upload:
	datadog-ci synthetics upload-application \
		--mobileApp ".build/Runner.ipa" \
		--mobileApplicationId "${S8S_APPLICATION_ID}" \
		--versionName "$(shell agvtool vers -terse)" \
		--latest
