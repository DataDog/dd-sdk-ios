# DatadogRUM — Swift 6 Structured Concurrency TODOs

## 1. ✅ Eliminate fire-and-forget `Task` writes in scopes

**Status**: Done

**What was done**: `Writer.write(value:metadata:)` was changed from `async` to
synchronous. `FileWriter` internally uses an `AsyncStream<Data>` drain loop —
encoding happens synchronously on the caller thread, only file I/O is dispatched
to the orchestrator actor. This means scopes call `writer.write(value: event)`
directly — no `Task`, no `await`, no fire-and-forget.

The implementation matches **Option A** (buffered synchronous writer) from the
original analysis, combined with **Option C** (serial write channel). Encoding
is synchronous at the call site (Option A), while the file writes are serialized
through the `FileWriter`'s internal `AsyncStream` (Option C).

**What this resolved**:
- ✅ Ordering — events are enqueued in the order `writer.write()` is called
- ✅ Backpressure — handled by the `AsyncStream` buffer
- ✅ Structured lifetime — no `Task` escaping scope boundaries
- ✅ `completionHandler()` — fires synchronously right after `writer.write()`

**Files changed** (scope-side — all `Task { await writer.write(...) }` removed):
- `RUMViewScope.sendViewUpdateEvent`
- `RUMViewScope.sendErrorEvent`
- `RUMViewScope.sendLongTaskEvent`
- `RUMUserActionScope.sendActionEvent`
- `RUMResourceScope.sendResourceEvent`
- `RUMResourceScope.sendErrorEvent`
- `RUMFeatureOperationManager`
- `RUMAppLaunchManager`

## 2. ✅ Convert `TelemetryReceiver` to an actor

**Status**: Done

**What was done**: `TelemetryReceiver` was converted from
`final class: @unchecked Sendable` to an `actor`. The `@ReadWriteLock` on
`recordState` was removed — actor isolation now protects the mutable state
directly.

Key design decisions:
- `receive(message:)` and `receive(telemetry:)` are `nonisolated` to satisfy the
  synchronous `FeatureMessageReceiver` protocol. They do lightweight switching and
  dispatch to actor-isolated `async` methods via `Task { await self... }`.
- `let` properties (`featureScope`, `dateProvider`, `sampler`,
  `configurationExtraSampler`) are marked `nonisolated` — safe to access from
  non-isolated context since they are immutable.
- `sampled(event:)` is `nonisolated` — creates a throwaway `Sampler`, no state access.
- `record(event:operation:)` is actor-isolated — directly mutates `recordState`
  (session tracking, deduplication, count limits) without any lock.
- The operation closure is `(DatadogContext, Writer) -> Void` (non-async) since
  `writer.write()` is synchronous.

**Supporting changes in `DatadogInternal`**:
- Added `Sendable` conformance to `ConfigurationTelemetry`, `MetricTelemetry`,
  `UsageTelemetry`, `UsageTelemetry.Event`, and `UsageTelemetry.Event.ViewLoadingTime`
  (simple value types that were missing the annotation, needed to safely cross
  isolation boundaries in `Task` closures).

## 3. ✅ Fix side effects after fire-and-forget writes

**Status**: Done — resolved naturally by TODO #1

**What happened**: Since `Writer.write()` is now synchronous, the counter
increments and flag mutations that follow `writer.write()` execute in the
correct order:

```swift
// sendLongTaskEvent — now fully synchronous
writer.write(value: event)     // enqueues synchronously
longTasksCount += 1            // runs after the write is enqueued
needsViewUpdate = true         // triggers view update with correct count
```

Events are enqueued in FIFO order by `FileWriter`'s internal `AsyncStream`,
so a view update event is always written after the long task/error event that
triggered it.

## 4. Audit remaining fire-and-forget Tasks in integrations

**Status**: Partially addressed

**Current state**: Several integration/instrumentation files use fire-and-forget
Tasks. These fall into two categories:

### Necessary — bridging `async` APIs from synchronous `receive(message:)`

These `Task` blocks exist because `receive(message:)` is synchronous but the
code needs to call `await featureScope.eventWriteContext()`:

| File | Occurrences | Purpose |
|------|-------------|---------|
| `TelemetryReceiver` | 5 | Write telemetry events (debug, error, config, metric, usage) — now actor-isolated async methods |
| `WebViewEventReceiver` | 2 | Write RUM/telemetry events from web views — now actor-isolated async methods |
| `CrashReportReceiver` | 2 | Send crash as RUM error |
| `WatchdogTerminationReporter` | 1 | Send termination event |
| `AnonymousIdentifierManager` | 1 | Track anonymous ID |

**Resolution**: These will be resolved when `FeatureMessageReceiver.receive(message:)`
becomes `async`. At that point, receivers can directly `await` the write context
without spawning a `Task`.

### Necessary — bridging `async` internal methods from synchronous entry points

| File | Occurrences | Purpose |
|------|-------------|---------|
| `WatchdogTerminationMonitor` | 2 | Start async check, update app state |
| `FatalAppHangsHandler` | 2 | Store hang data, report fatal hang |

**Resolution**: These are fire-and-forget by design — they kick off async work
from synchronous system callbacks. The `Task` pattern is appropriate here.
`FatalAppHangsHandler` uses `Task { [processID, featureScope] in }` which
correctly captures only `Sendable` values.

### Summary

| Category | Count | Actionable now? |
|----------|-------|-----------------|
| Blocked on async `receive(message:)` | 11 | No — same blocker as TODO #5 |
| Intentional fire-and-forget from sync entry points | 4 | No — correct pattern |

## 5. Make `FeatureMessageReceiver.receive(message:)` async

**Status**: Not started — requires cross-module coordination

**Why**: The synchronous `receive(message:)` protocol forces all receivers to
use fire-and-forget `Task` blocks when they need to call `async` APIs like
`featureScope.eventWriteContext()`. Making it `async` would:
- Allow receivers to directly `await` their write contexts
- Eliminate 11 fire-and-forget Tasks across DatadogRUM receivers
- Enable more receivers to become actors (see TODO #6)

**Impact**: This is a `DatadogInternal` protocol change that affects every module:
- `DatadogRUM`: `TelemetryReceiver`, `WebViewEventReceiver`, `CrashReportReceiver`,
  `WatchdogTerminationReporter`, `AnonymousIdentifierManager`, `FlagEvaluationReceiver`,
  `ErrorMessageReceiver`, `FatalErrorContextNotifier`
- `DatadogLogs`: `LogMessageReceiver`, `WebViewLogReceiver`
- `DatadogCrashReporting`: `CrashReportSender`, `CrashContextCoreProvider`
- `DatadogCore`: `MessageBus`, `CombinedFeatureMessageReceiver`

**Blocked on**: Decision on whether `MessageBus` should call receivers via
`await receiver.receive(message:)` or deliver through `AsyncStream` per-receiver.

## 6. Remaining `@unchecked Sendable` types — candidates for actors or cleanup

**Status**: Partially done

### 6a. ✅ Dropped `@unchecked Sendable` (all stored properties are `Sendable`)

| Type | Kind | Action taken |
|------|------|-------------|
| `FatalAppHang` | struct | Changed `@unchecked Sendable` → `Sendable` |
| `objc_HeaderCaptureRule` | final class | Changed `@unchecked Sendable` → `Sendable`. Also made `HeaderCaptureRule` enum `Sendable`. |
| `objc_TrackResourceHeaders` | final class | Changed `@unchecked Sendable` → `Sendable`. Also made `TrackResourceHeaders` enum `Sendable`. |
| `SendableJSON` | private struct | ❌ Cannot — `Any` is not `Sendable`. Wrapper is correct. |

### 6b. ✅ Dropped `@unchecked Sendable` after making `RUMUUIDGenerator: Sendable`

| Class | Action taken |
|-------|-------------|
| `WatchdogTerminationReporter` | Changed `@unchecked Sendable` → `Sendable`. All `let` dependencies (`FeatureScope`, `DateProvider`, `RUMUUIDGenerator`) are now `Sendable`. |
| `AnonymousIdentifierManager` | Changed `@unchecked Sendable` → `Sendable`. Made `final class`. All `let` dependencies are `Sendable`. |
| `FatalAppHangsHandler` | ❌ Kept `@unchecked Sendable` — `FatalErrorContextNotifying` is not `Sendable` (has mutable properties protected by `@ReadWriteLock`). |

Supporting change: Made `RUMUUIDGenerator` protocol conform to `Sendable`.

### 6c. Actor conversions

| Class | Status | Notes |
|-------|--------|-------|
| `WebViewEventReceiver` | ✅ Done | Converted to `actor`. `nonisolated func receive(message:)` dispatches to actor-isolated `writeRUMEvent`/`writeTelemetryEvent`. Made `RUMCommandSubscriber: Sendable` and `ViewCache: @unchecked Sendable` to support nonisolated access. |
| `WatchdogTerminationMonitor` | ❌ Skipped | `update(viewEvent:)` is called synchronously from `RUMViewScope.process()` (scope processing loop). `flush()` is synchronous via `Flushable` protocol. Actor would require `await` for both, breaking the synchronous scope contract. Keep `@ReadWriteLock`. |
| `AccessibilityReader` | ❌ Skipped | `state` property is read synchronously from `RUMViewScope.process()`. Making `@MainActor` would require `await` for reads, breaking scope processing. Keep `@ReadWriteLock`. |
| `ValuePublisher<Value>` | ❌ Skipped | Uses concurrent reads + barrier writes pattern that actors don't support. High-effort, medium-risk. Keep `DispatchQueue`. |
| `VitalRefreshRateReader` | ❌ Skipped | `ContinuousVitalReader` protocol methods are synchronous. Display link callback `didUpdateFrame` must be synchronous. Making `@MainActor` would require protocol changes and `await` at call sites. |

### 6d. Complex — requires architectural decisions

| Class | Why it's complex |
|-------|-----------------|
| `Monitor` | Uses `AsyncStream` command channel for sequential processing. Mutable state (`attributes`, `debugging`) is only mutated inside the `for await` loop — effectively single-threaded already. The `@unchecked Sendable` exists because the class is `final` with mutable `var` properties that the compiler can't verify are loop-confined. Converting to actor would conflict with the existing `AsyncStream` processing model (actor reentrancy vs. stream ordering). The current design is sound — the `@unchecked` annotation documents that safety is guaranteed by the stream's sequential consumption. **Recommendation**: Keep as-is. |
| `RUMAppLaunchManager` | Has mutable state (`timeToInitialDisplay`, `timeToFullDisplay`, `startupType`, `startupTypeHandler`) but is only accessed from `RUMViewScope.process()` (the scope processing loop). The `Task` in `writeTTIDVitalEvent` captures `self` weakly and mutates `startupType` — this is a race if `process()` is called again before the Task completes. However, `process()` guards with `timeToInitialDisplay == nil` so the Task only fires once. **Recommendation**: Consider making the `Task` body's writes to `self.startupType` explicit via a callback or restructuring to avoid the potential race. Low priority. |

### 6e. ✅ `CrashReportReceiver` — dropped `@unchecked Sendable`

**What was done**: Made all RUM event mapper type aliases `@Sendable`:
- `RUM.ViewEventMapper = @Sendable (RUMViewEvent) -> RUMViewEvent`
- `RUM.ResourceEventMapper = @Sendable (RUMResourceEvent) -> RUMResourceEvent?`
- `RUM.ErrorEventMapper = @Sendable (RUMErrorEvent) -> RUMErrorEvent?`
- `RUM.ActionEventMapper = @Sendable (RUMActionEvent) -> RUMActionEvent?`
- `RUM.LongTaskEventMapper = @Sendable (RUMLongTaskEvent) -> RUMLongTaskEvent?`

This made `RUMEventsMapper` fully `Sendable` (all stored properties are now
`Sendable`), which in turn allowed `CrashReportReceiver` to drop `@unchecked
Sendable` and use plain `Sendable`.

Also updated ObjC bridge mapper setters to accept `@Sendable` closures.

**Note**: This is a public API change — existing customer closures that capture
mutable state will now get a compiler warning. This is the correct behavior
since mappers are called from async contexts.

## 7. Remaining `@ReadWriteLock` usage — candidates for actor isolation

**Status**: Not started

| File | Property | Actor candidate? | Notes |
|------|----------|-------------------|-------|
| `WatchdogTerminationMonitor` | `currentState` | ✅ Yes | See TODO #6 |
| `FatalErrorContextNotifier` | `sessionState`, `view`, `globalAttributes` | ⚠️ Complex | Multiple mutable properties, called from scopes |
| `SessionEndedMetricController` | `metricsBySessionID` | ❌ No | Called synchronously from scope processing (`RUMViewScope`, `RUMSessionScope`, `RUMApplicationScope`, `RUMUserActionScope`). Actor would require `await` at every call site. |
| `DisplayLinker` | `renderLoopReaders` | ⚠️ Complex | Display link callback context |
| `FirstFrameReader` | `isActive` | ❌ Simple | Single bool — may not justify actor overhead |
| `ViewCache` | `views` | ⚠️ Complex | Accessed from scope processing. Now `@unchecked Sendable` (needed for `WebViewEventReceiver` actor). |
| `AppHangsWatchdogThread` | `mainThreadID`, `onBeforeSleep` | ❌ No | Must stay as thread — see note below |
| `AccessibilityReader` | `state` | ✅ Yes | See TODO #6 |

**Note on `AppHangsWatchdogThread`**: This class intentionally uses a raw
`Thread` subclass to detect main thread hangs. It cannot use structured
concurrency — an actor or `Task` on the cooperative thread pool could itself
be blocked by the same hang it's trying to detect. The `@ReadWriteLock` usage
here is correct and should remain.

## 8. Remaining `nonisolated(unsafe)` usage — cleanup opportunities

**Status**: Not started

### 8a. Necessary — cannot be removed

| File | Property | Why it must stay |
|------|----------|-----------------|
| `RUMCommand.swift` | `continuation: CheckedContinuation<Void, Never>` on `RUMFlushCommand` | `CheckedContinuation` is not `Sendable`. The continuation is created outside the processing loop (in `flush()`) and resumed inside the `for await` loop. It crosses isolation boundaries by design. `nonisolated(unsafe)` is the only option unless `CheckedContinuation` gains `Sendable` conformance. |
| `UIScrollViewSwizzler` | `proxyKey: Void?` (static) | `objc_setAssociatedObject` requires a pointer to a static var. The `static var` triggers the concurrency checker. This is standard ObjC runtime interop — the key is only used for its address, never mutated after initialization. |
| `UIScrollViewSwizzler` | `unsafeDelegate`, `unsafeHandler`, `unsafePreviousImpl` (locals in swizzle block) | These are captured from a `@convention(block)` closure and used inside `MainActor.assumeIsolated`. The closure itself is not `@Sendable` (ObjC block convention), so the compiler cannot verify safety. The values are used immediately within the same synchronous call — no actual race. |
| `UIApplicationSwizzler` | `handler: RUMActionsHandling` (stored), `weakHandler` (local) | Same pattern as `UIScrollViewSwizzler`. The `handler` is a `let` stored property, but `RUMActionsHandling` is a non-`Sendable` protocol. The `weakHandler` local is captured in a `@convention(block)` closure and used inside `MainActor.assumeIsolated`. Both are necessary for ObjC swizzling. |
| `RUM+objc.swift` | `objcPredicate: AnyObject?` on `UIKitRUMActionsPredicateBridge` | Bridges an ObjC predicate object (`objc_UITouchRUMActionsPredicate` or `objc_UIPressRUMActionsPredicate`) that is `AnyObject` — not `Sendable`. The bridge struct conforms to `UITouchRUMActionsPredicate & UIPressRUMActionsPredicate` (which are `@MainActor` protocols). The `let` property is set once at init and only read on `@MainActor`. `nonisolated(unsafe)` is necessary because `AnyObject` cannot satisfy `Sendable`. |

### 8b. Set-once pattern — could be improved but low priority

| File | Property | Current pattern | Possible improvement |
|------|----------|----------------|---------------------|
| `RUMScrollHandler` | `subscriber: RUMCommandSubscriber?` | Set once in `nonisolated func publish(to:)` during setup, only read afterwards on `@MainActor`. The class is `@MainActor` but `publish(to:)` is `nonisolated`. | Could make `publish(to:)` `@MainActor` if callers can be made async. Alternatively, use `init` injection instead of post-init `publish(to:)`. Low priority — the set-once pattern is safe in practice. |
| `RUMViewsHandler` | `subscriber: RUMCommandSubscriber?` | Identical pattern to `RUMScrollHandler`. | Same improvement path. Both handlers are `@MainActor`, and the `subscriber` is only read on MainActor after the initial set. |

### 8c. ✅ ViewHitchesReader — reverted to `final class: @unchecked Sendable`

`ViewHitchesReader` was declared as an `actor` but used `NSLock` + 9
`nonisolated(unsafe)` properties instead of actor isolation, because both the
write path (`didUpdateFrame`, CADisplayLink callback) and read paths
(`dataModel`, `telemetryModel`, `isActive`, called from `RUMViewScope.process()`)
require synchronous `nonisolated` access.

**What was done**: Reverted from `actor` to `final class: @unchecked Sendable`.
Removed all `nonisolated(unsafe)` qualifiers and `nonisolated` method annotations.
The `NSLock` remains as the correct synchronization primitive. This is more honest
about the actual synchronization model — no actor isolation is used.
