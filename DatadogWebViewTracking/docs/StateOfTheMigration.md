# DatadogWebViewTracking — Swift 6 Migration Status

Current state of the Swift 6 / modern concurrency migration for the `DatadogWebViewTracking` module.
Use this to pick up remaining work or as a reference when migrating other modules.

---

## Completed

### `@MainActor` isolation

- `WebViewTracking.enable(webView:hosts:hostsSanitizer:logsSampleRate:in:)` — `@MainActor`
- `WebViewTracking.disable(webView:in:)` — `@MainActor`
- `WebViewTracking.enableOrThrow(tracking:hosts:hostsSanitizer:logsSampleRate:in:)` — `@MainActor`
- `DDScriptMessageHandler` — explicit `@MainActor`, leans into `WKScriptMessageHandler` isolation
- Obj-C bridge `enable` / `disable` — `@MainActor`

### DispatchQueue removal

- `DDScriptMessageHandler.queue` — removed entirely; `emitter.send()` runs
  synchronously on the main actor (work is lightweight JSON parsing + message dispatch)

### `runOnMainThreadSync` removal

- Replaced by `@MainActor` annotation on `enable` / `disable` / `enableOrThrow`
- Compile-time guarantee instead of runtime dispatch

### `Flushable` conformance removal

- `DDScriptMessageHandler` no longer conforms to `Flushable`
- `flush()` method removed — no async work to synchronise with
- `WKUserContentControllerMock.flush()` removed from `TestUtilities`

### Tests migrated

- `WebViewTrackingTests` — annotated `@MainActor` to match production context
- No callback-to-async test changes needed (no callbacks in this module)

### Deployment target alignment

- `DatadogWebViewTrackingTests iOS` target in `project.pbxproj` — set
  `IPHONEOS_DEPLOYMENT_TARGET = 13` for Debug, Release, and Integration configurations

---

## Remaining — explicit Sendable annotations

These types lack explicit `Sendable` conformance. In Swift 6 mode, non-public
types get implicit Sendable within the module, but explicit annotation is
better for documentation and cross-module use.

### Medium priority — internal types

| Type | File | Notes |
|------|------|-------|
| `MessageEmitter` | `MessageEmitter.swift` | `final class` with `weak var core`; stays on `@MainActor` so no boundary crossing currently |
| `WebViewMessageError` | `MessageEmitter.swift` | Enum with `String` raw value — trivially Sendable |
| `AbstractMessageEmitter` | `AbstractMessageEmitter.swift` | Protocol; consider adding `: Sendable` |

### Blocked on DatadogInternal

These types conform to protocols in `DatadogInternal`. Adding `Sendable`
requires the protocols to be `Sendable` first:

| Type | File | Depends on |
|------|------|------------|
| `DDScriptMessageHandler` | `DDScriptMessageHandler.swift` | N/A — `@MainActor` class, Sendable by isolation |
| `WebViewTrackingFeature` (if exists) | — | `DatadogFeature: Sendable` (verify) |

---

## Not changing

| Item | Reason |
|------|--------|
| `MessageEmitter` is not `@unchecked Sendable` | Not needed — stays within `@MainActor` isolation, no boundary crossing |
| No `async/await` conversions | Module has no callback-based APIs or completion handlers |
| No `withCheckedContinuation` bridging | Module doesn't use `eventWriteContext`; messages go through core's message bus |

---

## Recent changes

### `MessageSending` protocol update

The `else fallback:` parameter has been removed from `MessageSending.send(message:)`.
`MessageEmitter.send(log:in:)`, `send(rum:in:)`, and `send(record:view:slotId:in:)`
previously used `core.send(message:, else: { DD.logger.warn(...) })`. These now call
`core.send(message:)` without a fallback — warnings for disabled features are silently
dropped if no receiver handles the message.

---

## Reference

- `ModernConcurrency.md` (same folder) — patterns and lessons learned specific to WebViewTracking
- `docs/ModernConcurrency.md` (repo root) — general migration guide with cross-module conclusions
- `DatadogLogs/Resources/StateOfTheMigration.md` — reference for a more complex migration
- `Package.swift` — `DatadogWebViewTracking` uses `.swiftLanguageMode(.v6)`, `DatadogInternal` also uses `.swiftLanguageMode(.v6)`
