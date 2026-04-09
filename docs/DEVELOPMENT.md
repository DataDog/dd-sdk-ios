# Development Recipes

## Where to Add New Code

### New Feature Module (e.g., DatadogNotifications)
1. Create `DatadogNotifications/` with `Sources/` and `Tests/` subdirectories
2. Entry point: `Notifications.swift`, config: `NotificationsConfiguration.swift`
3. Feature plugin: `Feature/NotificationsFeature.swift` (implements `DatadogRemoteFeature`)
4. Update `Datadog.xcworkspace` and any relevant `.pbxproj` files

### New RUM Instrumentation
1. Create files in `DatadogRUM/Sources/Instrumentation/<InstrumentationName>/`
2. Follow existing patterns (e.g., `Resources/`, `Actions/`, `AppHangs/`, `Views/`)
3. Register in `RUMInstrumentation.swift`
4. Add tests in `DatadogRUM/Tests/RUMTests/Instrumentation/`

### New RUM Command
1. Add struct to `DatadogRUM/Sources/RUMMonitor/RUMCommand.swift` (implements `RUMCommand` protocol)
2. Include timestamp, attributes, and any decision hints (e.g., `canStartBackgroundView`)
3. Add public API method to `RUMMonitorProtocol.swift` and implement in `Monitor.swift`
4. Add processing logic in the appropriate scope
5. Add tests in `DatadogRUM/Tests/RUMTests/Scopes/`
6. Update API surface: `make api-surface`

### New Context Provider
1. Add the property to `DatadogContext` in `DatadogInternal/Sources/Context/`
2. Create `DatadogCore/Sources/Core/Context/<ProviderName>Publisher.swift` implementing `ContextValuePublisher`
3. Subscribe to relevant system notifications
4. Register the publisher in `DatadogContextProvider` initialization
5. Add tests in `DatadogCore/Tests/`

### Shared Internal Types (used by multiple features)
1. Add to `DatadogInternal/Sources/` in the appropriate subdirectory
2. Add tests in `DatadogInternal/Tests/`
3. Changes here affect ALL modules — proceed with extreme caution

## RFC Process for Major Changes

If you're about to make a change that modifies public API significantly, changes data collection behavior, affects initialization/lifecycle, introduces new configuration options, or changes network request format/frequency — **STOP and inform the engineer.** Such changes require internal RFC approval and cross-platform alignment.

## Quick Reference

| Task | Command |
|------|---------|
| Setup | `make` |
| Lint | `./tools/lint/run-linter.sh` |
| Test iOS | `make test-ios SCHEME="<scheme>"` |
| All iOS tests | `make test-ios-all` |
| Test watchOS | `make test-watchos SCHEME="<scheme>"` |
| Test visionOS | `make test-visionos SCHEME="<scheme>"` |
| UI tests | `make ui-test TEST_PLAN="Default"` |
| Build SPM | `make spm-build-ios` |
| API surface | `make api-surface` |
| Verify API surface | `make api-surface-verify` |
| License check | `make license-check` |
| Generate RUM models | `make rum-models-generate GIT_REF=master` |
| Generate SR models | `make sr-models-generate GIT_REF=master` |
| Clean | `make clean` |
