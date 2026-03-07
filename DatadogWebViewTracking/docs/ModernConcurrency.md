# Modern Concurrency Migration Guide — DatadogWebViewTracking

Patterns and lessons learned from migrating `DatadogWebViewTracking` to Swift 6.
Use this alongside the `DatadogLogs/Resources/ModernConcurrency.md` reference
when applying the same migration to other feature modules.

---

## 1. WKScriptMessageHandler infers @MainActor on the entire class

In Swift 6, conforming to `WKScriptMessageHandler` makes the class `@MainActor`
isolated. This happens because Apple annotated the protocol with `@MainActor`.

**Impact:** Every stored property and method on `DDScriptMessageHandler` becomes
`@MainActor` by default, including properties and protocol conformances that
shouldn't be main-actor-bound.

**Symptom:**
```
error: main actor-isolated instance method 'flush()' cannot be used
to satisfy nonisolated requirement from protocol 'Flushable'
```

---

## 2. Leaning into @MainActor instead of fighting it

The original code worked around WebKit's main-thread requirement with a
`DispatchQueue` to offload work to a background thread. In Swift 6, this
pattern creates friction: the class is `@MainActor`, so every value crossing
to the background queue needs `Sendable` conformance or `nonisolated` escape
hatches.

**Better approach:** Lean into `@MainActor`. The work done in the handler
(JSON decode a small message, dispatch to core's message bus) is lightweight
enough to run synchronously on the main actor.

### Before (DispatchQueue + nonisolated workarounds)
```swift
internal class DDScriptMessageHandler: NSObject, WKScriptMessageHandler {
    nonisolated let emitter: MessageEmitter       // needs Sendable
    nonisolated let queue = DispatchQueue(...)

    func userContentController(..., didReceive message: WKScriptMessage) {
        nonisolated(unsafe) let body = message.body // Any is not Sendable
        queue.async { [emitter] in
            emitter.send(body: body, slotId: hash)
        }
    }
}
```

### After (embrace @MainActor)
```swift
@MainActor
internal class DDScriptMessageHandler: NSObject, WKScriptMessageHandler {
    let emitter: MessageEmitter                    // no Sendable needed

    func userContentController(..., didReceive message: WKScriptMessage) {
        let body = message.body                    // stays on main actor
        emitter.send(body: body, slotId: hash)
    }
}
```

**Benefits:**
- No `DispatchQueue`, no `nonisolated`, no `nonisolated(unsafe)`
- `MessageEmitter` doesn't need `@unchecked Sendable`
- `message.body: Any` doesn't need a Sendable workaround
- Tests run faster (no async dispatch overhead)

**When to keep a DispatchQueue instead:**
- The offloaded work is computationally expensive (image processing, large
  data transforms, etc.)
- The work involves blocking I/O that would stall the UI

---

## 3. Removing `Flushable` conformance

The original `DDScriptMessageHandler` conformed to `Flushable` with
`queue.sync { }` to block until pending async work completed. With the
`@MainActor` design, all work runs synchronously — there's nothing to flush.
The conformance and its test-mock counterpart (`WKUserContentControllerMock.flush()`)
were removed entirely.

---

## 4. Replacing `runOnMainThreadSync` with `@MainActor`

The legacy pattern used `runOnMainThreadSync { }` to dispatch WebKit calls to
the main thread at runtime. With Swift 6, `@MainActor` makes this a
compile-time guarantee:

### Before
```swift
public static func enable(webView: WKWebView, ...) {
    do {
        try runOnMainThreadSync {
            try enableOrThrow(tracking: webView.configuration.userContentController, ...)
        }
    } catch { ... }
}
```

### After
```swift
@MainActor
public static func enable(webView: WKWebView, ...) {
    do {
        try enableOrThrow(tracking: webView.configuration.userContentController, ...)
    } catch { ... }
}
```

**Why this is correct:**
- These methods interact with `WKWebView` and `WKUserContentController`,
  which are `@MainActor` in Swift 6
- They were already required to run on the main thread (runtime crash otherwise)
- `@MainActor` makes the requirement a compile-time check
- `runOnMainThreadSync` is no longer needed — the annotation is sufficient

**Impact on callers:**
- UIKit callers (typically `@MainActor`) call directly with no change
- Background callers now use `await` instead of relying on implicit dispatch

---

## 5. Obj-C bridge with @MainActor

`@objc` methods CAN be `@MainActor`. For the WebView bridge, the Obj-C
methods already had to run on the main thread, so adding `@MainActor` is
a natural fit:

```swift
@objc
@MainActor
public static func enable(webView: WKWebView, hosts: Set<String>, ...) {
    WebViewTracking.enable(webView: webView, hosts: hosts, ...)
}
```

---

## 6. Test class annotation

When production methods are `@MainActor`, test classes that call them need
`@MainActor` too:

```swift
@MainActor
class WebViewTrackingTests: XCTestCase {
    func testItAddsUserScript() throws {
        // Can call @MainActor methods directly — no `await` needed
        try WebViewTracking.enableOrThrow(tracking: controller, ...)
    }
}
```

Test methods on a `@MainActor` class run on the main actor, matching the
production context. No other test changes were needed.

---

## 7. Deployment target alignment in Xcode project

When bumping the platform minimum in `Package.swift` (e.g. `.iOS(.v13)`),
test targets in the `.xcodeproj` may not inherit the change. If a test
target doesn't set `IPHONEOS_DEPLOYMENT_TARGET` explicitly, it inherits
from the project-level default (which may still be iOS 12).

**Fix:** Add `IPHONEOS_DEPLOYMENT_TARGET = 13;` to each build configuration
(Debug, Release, Integration) of the test target in `project.pbxproj`.

---

## 8. Differences from the DatadogLogs migration

| Aspect | DatadogLogs | DatadogWebViewTracking |
|--------|-------------|------------------------|
| **Callback → async** | `LogEventMapper` callback converted to `async -> T?` | No callbacks to convert |
| **eventWriteContext** | Bridged to async with `withCheckedContinuation` | Not used (messages go through core's message bus) |
| **Thread-sensitive captures** | `dateProvider.now`, `Thread.current.dd.name` | Not applicable — everything stays on main actor |
| **Actor vs ReadWriteLock** | `SynchronizedAttributes` kept as `ReadWriteLock` | No mutable synchronized state |
| **`@MainActor` on public API** | Not needed (logging has no UI dependency) | Required (WebKit APIs are `@MainActor`) |
| **DispatchQueue** | Not applicable | Removed — lean into `@MainActor` instead |
| **Sendable** | Multiple types needed `@unchecked Sendable` | Not needed — no isolation boundary crossings |

---

## 9. Checklist (WebViewTracking-specific)

1. **Make `DDScriptMessageHandler` explicitly `@MainActor`** — lean into the isolation
2. **Remove `DispatchQueue`** — run `emitter.send()` synchronously on main actor
3. **Mark `flush()` as `nonisolated`** — no-op since all work is synchronous
4. **Add `@MainActor` to `enable`/`disable`/`enableOrThrow`** — WebKit APIs require it
5. **Remove `runOnMainThreadSync`** — `@MainActor` replaces it
6. **Add `@MainActor` to Obj-C bridge** — matches Swift API
7. **Add `@MainActor` to test class** — matches production context
8. **Fix test target deployment target** in `.xcodeproj`
