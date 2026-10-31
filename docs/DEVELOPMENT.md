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

## Documentation Gate

The documentation gate uses [FactoryKit](https://github.com/ddoghq/factorykit) to examine tracked documentation. It blocks a change that adds a broken local link or anchor. Findings that exist before the change do not block. The gate also gives advisory reminders to review the affected documentation.

`scripts/foundation_check.py` selects the entry document (`AGENTS.md`) and the documentation map (`docs/README.md`). `factoryspec.yaml` and `factory/` record that selection.

1. Install the runtime one time. It installs a pinned FactoryKit version outside the repository and needs read access to `ddoghq/factorykit`:

   ```bash
   make factorykit-setup
   ```

2. Run the gate. By default, it compares the worktree with the merge-base of `origin/develop`:

   ```bash
   make docs-gate
   make docs-gate SNAPSHOT=index AGAINST=HEAD   # staged changes only
   ```

The `git-commit` and `open-pr` skills run the gate when the runtime is installed. CI does not run the gate. To use a new FactoryKit version, change `FACTORYKIT_SHA` in `tools/factorykit/common.sh`.

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
| Documentation gate | `make docs-gate` |
| Generate RUM models | `make rum-models-generate GIT_REF=master` |
| Generate SR models | `make sr-models-generate GIT_REF=master` |
| Clean | `make clean` |
