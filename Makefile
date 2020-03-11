all: dependencies xcodeproj-sdk xcodeproj-httpservermock templates examples
.PHONY : examples

dependencies:
		@echo "⚙️  Validating dependencies..."
		@brew list swiftlint &>/dev/null || brew install swiftlint
		@echo "OK 👌"

xcodeproj-sdk:
ifdef ci
		@echo "⚙️  Generating 'Datadog.xcodeproj' for CI..."
		swift package generate-xcodeproj --skip-extra-files
else
		@echo "⚙️  Generating 'Datadog.xcodeproj' for development..."
		swift package generate-xcodeproj --enable-code-coverage --xcconfig-overrides Datadog.xcconfig --skip-extra-files
endif
		@echo "OK 👌"

xcodeproj-httpservermock:
		@echo "⚙️  Generating 'HTTPServerMock.xcodeproj'..."
		@cd instrumented-tests/http-server-mock/ && swift package generate-xcodeproj
		@echo "OK 👌"

templates:
		@echo "⚙️  Installing Xcode templates..."
		./tools/xcode-templates/install-xcode-templates.sh
		@echo "OK 👌"

examples:
		@echo "⚙️  Generating 'examples/examples-secret.xcconfig' file..."
		./tools/config/generate-examples-config-template.sh
		@echo "OK 👌"

# Tests if current branch ships a valid SPM package.
test-spm:
	@cd dependency-manager-tests/spm && $(MAKE)
