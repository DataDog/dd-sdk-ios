all: tools dependencies xcodeproj-httpservermock templates examples benchmark
.PHONY : examples tools

tools:
		@echo "⚙️  Installing tools..."
		@brew list swiftlint &>/dev/null || brew install swiftlint
		@echo "OK 👌"

dependencies:
ifneq ("$(wildcard ./Cartfile)","")
		@echo "⚙️  Cartfile found, bootstrapping..."
		@carthage bootstrap --platform iOS
else
		@echo "⚙️  Cartfile not found, ignoring."
		@echo "OK 👌"	
endif

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

# Tests if current branch ships a valid Carthage project.
test-carthage:
		@cd dependency-manager-tests/carthage && $(MAKE)

# Tests if current branch ships a valid Cocoapods project.
test-cocoapods:
		@cd dependency-manager-tests/cocoapods && $(MAKE)
