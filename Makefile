all: dependencies xcodeproj-sdk xcodeproj-httpservermock templates examples
.PHONY : examples

dependencies:
		@echo "⚙️  Validating dependencies..."
		@brew list swiftlint &>/dev/null || brew install swiftlint
		@echo "OK 👌"

xcodeproj-sdk:
		@echo "⚙️  Generating 'Datadog.xcodeproj'..."
		swift package generate-xcodeproj --enable-code-coverage --xcconfig-overrides Datadog.xcconfig
		@echo "OK 👌"

xcodeproj-httpservermock:
		@echo "⚙️  Generating 'HTTPServerMock.xcodeproj'..."
		cd tools/http-server-mock/ && swift package generate-xcodeproj
		@echo "OK 👌"	

templates:
		@echo "⚙️  Installing Xcode templates..."
		./tools/xcode-templates/install-xcode-templates.sh
		@echo "OK 👌"

examples:
		@echo "⚙️  Generating 'examples/examples-secret.xcconfig' file..."
		./tools/config/generate-examples-config-template.sh
		@echo "OK 👌"
