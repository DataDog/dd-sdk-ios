# Integration Tests

This project contains the UI integration tests for the iOS SDK. It consumes the SDK, `SRFixtures`, and `HTTPServerMock` through local Swift Package Manager references.

## Setup

Close Xcode, then open the workspace from the repository root:

```bash
make ui-tests-open
```

This passes two environment variables to Xcode before it resolves `Package.swift`:

- `DD_SDK_COMPILED_FOR_TESTING=1` enables the SDK's integration testing hooks.
- `DD_TEST_UTILITIES_ENABLED=1` exports the `TestUtilities` package product used by the test target.

Select the `IntegrationScenarios` scheme and a test plan to run tests. The test action uses `Debug`; the `Runner iOS` scheme runs the app with the optimized `Integration` configuration.

## Command line

Run a test plan from the repository root:

```bash
make ui-test TEST_PLAN="RUM"
```

`tools/ui-test.sh` sets both environment variables and Xcode resolves the package dependencies automatically. Use `make ui-test-all` to run every test plan.

For direct `xcodebuild` commands, pass both variables as well:

```bash
DD_SDK_COMPILED_FOR_TESTING=1 DD_TEST_UTILITIES_ENABLED=1 \
  xcodebuild -workspace IntegrationTests/IntegrationTests.xcworkspace \
  -scheme IntegrationScenarios -testPlan RUM \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Troubleshooting dependency resolution

If Xcode reports a missing `TestUtilities` product or SDK testing hook, close Xcode and reopen it with `make ui-tests-open` so package resolution receives the required environment variables. If resolution remains stale, use **File > Packages > Reset Package Caches**, then resolve the packages again.
