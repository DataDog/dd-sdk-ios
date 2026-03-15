# DatadogRUM — Swift 6 Migration Status

Current state of the Swift 6 / modern concurrency migration for the `DatadogRUM` module.
Use this to pick up remaining work or as a reference when migrating other modules.

---

## Completed

### Actor conversion: AppStateManager

`AppStateManager` was converted from a `class` with `@ReadWriteLock`, `DispatchGroup`,
and `DispatchQueue` to a Swift `actor`. This eliminated all manual synchronization.

- `AppStateManager` — now `actor AppStateManager: AppStateManaging`
- `AppStateManaging` — protocol marked `Sendable`, methods are `async`
  - `func updateAppState(state:) async`
  - `func fetchAppStateInfo() async -> (previous: AppStateInfo?, current: AppStateInfo)`
- `previousAppStateInfo()` and `currentAppStateInfo()` — removed from protocol,
  now `private` on the actor (callers use `fetchAppStateInfo()` instead)
- `updateAppStateInStore(block:)` — converted from callback-based to `async` using
  `withCheckedContinuation` to read the data store, then synchronous mutation + write
- Initialization — synchronous `init` kicks off `Task { await self.start() }`;
  callers awaiting `fetchAppStateInfo()` suspend via `pendingContinuations` until ready

### async/await conversions

- `WatchdogTerminationChecker.isWatchdogTermination(launch:)` — completion handler
  removed, now `async -> (isWatchdogTermination: Bool, appState: AppStateInfo?)`
- `WatchdogTerminationMonitor.sendWatchTerminationIfFound(launch:)` — completion
  handler removed, now `async`
- `WatchdogTerminationMonitor.sendWatchTermination(state:)` — completion handler
  removed, now `async`; uses `withCheckedContinuation` to bridge `feature.context`
  and `rumDataStore.value` callbacks
- `WatchdogTerminationMonitor.start(launchReport:)` — uses `Task { [weak self] in }`
  to call async methods
- `RUMAppLaunchManager.writeTTIDVitalEvent(...)` — uses `Task { [weak self] in }` to
  `await dependencies.appStateManager.fetchAppStateInfo()`; extracts `activeViewUUID`
  and `activeViewPath` before the Task to avoid capturing non-Sendable `RUMViewScope`

### @MainActor isolation

- `RUM` enum — marked `@MainActor`; `enable()` wraps body in `runOnMainThreadSync`
  as a runtime safety net for GCD callers that bypass actor isolation
- `objc_RUM.enable(with:)` — marked `@MainActor`
- UIKit event processing chain — see `ModernConcurrency.md` (same folder) for full details

### Sendable conformances

- `AppStateManaging: Sendable` (protocol)
- `AppStateInfo: Codable, Sendable` (struct)
- `WatchdogTerminationChecker: Sendable` (final class, immutable `let` properties)
- `WatchdogTerminationMonitor: @unchecked Sendable` (final class, `@ReadWriteLock`
  protects `currentState`; all `let` properties are immutable after init)
- `RUMAppLaunchManager: @unchecked Sendable` (final class, runs on RUM scope's
  serial queue; mutable state is only accessed from that queue)
- See `ModernConcurrency.md` for additional Sendable conformances (`ValuePublisher`,
  `ViewHitchesReader`, `VitalRefreshRateReader`, `RUMDebugging`, etc.)

### DatadogInternal types made Sendable (for DatadogRUM consumption)

- `DatadogContext: @unchecked Sendable`
- `Writer: Sendable` (protocol)
- `LaunchReport: Sendable` (struct)
- `AttributeValue = Encodable & Sendable`
- `RUMErrorMessage.attributes`, `RUMFlagEvaluationMessage.value` → `Sendable`

### Patterns established

- **Actor with deferred init** — `AppStateManager` uses `Task { await start() }` in
  `init` with `pendingContinuations` to defer async setup while keeping `init` synchronous
- **`withCheckedContinuation`** — bridges callback-based `featureScope.context`,
  `rumDataStore.value`, and `rumDataStore.value(forKey:)` to `async`
- **Extract Sendable values before Task** — `RUMAppLaunchManager` extracts
  `activeViewUUID` and `activeViewPath` from non-Sendable `RUMViewScope` before
  the `Task` boundary, avoiding `@unchecked Sendable` boxes
- **`runOnMainThreadSync` + `@MainActor`** — `RUM.enable()` uses both: `@MainActor`
  for compile-time guarantees, `runOnMainThreadSync` as a runtime safety net for
  unstructured GCD callers

### Monitor: lock-free AsyncStream command pipeline

`Monitor` was converted from a `class` with `NSLock` (`scopeProcessingLock`) and
`@ReadWriteLock` (attributes, debugging) to a lock-free `final class: @unchecked Sendable`.

- `Monitor` — `final class: @unchecked Sendable` with `AsyncStream<RUMCommand>`
- `process(command:)` — fire-and-forget; yields to the stream and returns immediately
- `processFromStream(command:)` — `async`; the single processing method called from
  the `for await` loop on the cooperative thread pool
- `attributes` — `private var`, only mutated inside the loop via `RUMGlobalAttributeCommand`
- `debugging` — `private var`, only mutated inside the loop via `RUMSetDebugCommand`
- `scopeProcessingLock` — **removed** (stream serializes processing)
- `@ReadWriteLock` on attributes/debugging — **removed** (stream serializes mutations)
- `globalAttributes` on commands — set inside `processFromStream` before passing to
  the scope tree; methods no longer snapshot attributes at call time
- `updateCoreContext()` — eagerly computes RUM context inside the loop after each command
- `flush()` — `RUMFlushCommand` sentinel + `withCheckedContinuation` for test sync
- New command types: `RUMGlobalAttributeCommand` (attribute mutations),
  `RUMSetDebugCommand` (debug toggle), `RUMFlushCommand` (test sync)

### Tests migrated

- `AppStateManagerTests` — all tests converted to `async throws`; use
  `fetchAppStateInfo().previous` instead of `previousAppStateInfo()`
- `WatchdogTerminationCheckerTests` — uses `AppStateManagerMock` (synchronous init)
- `WatchdogTerminationMonitorTests` — uses `AppStateManagerMock`; `given()` helper
  is synchronous
- `RUMTests` — class marked `@MainActor`; calls to `RUM.enable()` are synchronous
- `MonitorTests` — all tests converted to `async throws`; use `await monitor.flush()`
- `Monitor+GlobalAttributesTests` — all tests converted to `async throws`; use
  `await monitor.flush()`

---

## Remaining — async/await conversions

These areas still use callback patterns that could benefit from `async/await`:

| Area | File | Notes |
|------|------|-------|
| `RUMEventsMapper` | `RUMEventsMapper.swift` | Event mapping callbacks could become `async` |

> **Note:** `featureScope.context { }` has been converted to `async` (`FeatureScope.context`
> now returns `DatadogContext` directly). `rumDataStore.value(forKey:)` and
> `DataStore.value(forKey:)` have been converted to `async` as well.

---

## Remaining — Sendable conformances

### High priority — crossed across Task boundaries

| Type | File | Why |
|------|------|-----|
| `RUMScopeDependencies` | `RUMScopeDependencies.swift` | Captured in `Task` closures via `self.dependencies` in `RUMAppLaunchManager` |
| `RUMCommand` structs | `RUMCommand.swift` | Passed into `Task` closures (partially addressed — some commands are now Sendable) |

### Medium priority — internal types

| Type | File | Notes |
|------|------|-------|
| `RUMEventsMapper` | `RUMEventsMapper.swift` | Holds event mappers |
| `RUMEventBuilder` | `RUMEventBuilder.swift` | Creates RUM events |
| `RUMViewScope` | `RUMViewScope.swift` | Non-Sendable class; values must be extracted before `Task` boundaries |
| `SessionEndedMetricController` | `SessionEndedMetricController.swift` | Candidate for actor conversion |

### Blocked on DatadogInternal

These types conform to protocols in `DatadogInternal`. Adding `Sendable` requires
the protocols to be `Sendable` first:

| Type | File | Depends on |
|------|------|------------|
| `WatchdogTerminationReporting` | `WatchdogTerminationReporter.swift` | Protocol not `Sendable` |
| `Storage` | `DatadogInternal` | Protocol not `Sendable` |
| `RUMFeature` | `RUMFeature.swift` | `DatadogFeature: Sendable` |

> **Note:** `FeatureMessageReceiver` conformers are no longer blocked — the protocol
> has been simplified to `func receive(message: FeatureMessage)` (no `core:` param,
> no `Bool` return). Receivers needing core access now inject `FeatureScope` at init.

---

## Remaining — potential actor conversions

| Type | File | Current synchronization | Notes |
|------|------|------------------------|-------|
| `ValuePublisher` | `ValuePublisher.swift` | Concurrent `DispatchQueue` with barrier | Could become actor; verify subscribers don't need synchronous reads |
| `ViewHitchesReader` | `ViewHitchesReader.swift` | Serial `DispatchQueue` | Good actor candidate |
| `SessionEndedMetricController` | `SessionEndedMetricController.swift` | `@ReadWriteLock` | Could become actor if callers can be async |

---

## Not changing

| Item | Reason |
|------|--------|
| `@ReadWriteLock` on `WatchdogTerminationMonitor.currentState` | Synchronous reads required from `receive(message:)` |
| `runOnMainThreadSync` in `RUM.enable()` | Runtime safety net for GCD callers; complements `@MainActor` |
| `VitalInfoSampler.maximumFramesPerSecond` using `MainActor.assumeIsolated` | Default parameter evaluated from any thread; falls back to 60.0 |
| `DispatchQueue.main.async` in `RUMDebugging.debug()` | Used in `deinit`-adjacent context; `Task` has different lifetime semantics |
| RUM scope hierarchy (`RUMSessionScope`, `RUMViewScope`, etc.) remaining synchronous | The scope tree is a synchronous state machine (no I/O). The async boundary is at the Monitor level (stream + context fetching). Making scopes async would be a massive refactor with no benefit — the `for await` loop already serializes processing. |

---

## Reference

- `ModernConcurrency.md` (same folder) — patterns and decisions specific to DatadogRUM
- `docs/ModernConcurrency.md` (repo root) — cross-cutting lessons, reusable for all modules
- `Package.swift` — `DatadogRUM` uses `.swiftLanguageMode(.v6)`, `DatadogInternal` also uses `.swiftLanguageMode(.v6)`
