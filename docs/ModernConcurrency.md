# Modern Concurrency Migration — General Learnings

Cross-cutting lessons learned from migrating SDK feature modules to Swift 6.
Each module also has its own `Resources/ModernConcurrency.md` with
module-specific details:

- `DatadogLogs/Resources/ModernConcurrency.md`
- `DatadogWebViewTracking/Resources/ModernConcurrency.md`

---

## 1. Feature modules may naturally be `@MainActor`

Some feature modules interact exclusively with `@MainActor` Apple frameworks
(WebKit, UIKit, etc.). In Swift 6, these frameworks enforce `@MainActor`
isolation at compile time. Rather than fighting this with `nonisolated` escape
hatches and `Sendable` workarounds, **lean into the isolation**.

**Signs a module should be `@MainActor`:**
- Its public API takes UI types (`WKWebView`, `UIView`, etc.)
- Apple already requires its entry points to run on the main thread
- The work it does is lightweight (message routing, small JSON parsing, config)

**Example — WebViewTracking:**
`WebViewTracking.enable(webView:)` was already wrapped in `runOnMainThreadSync`.
Making it `@MainActor` replaced the runtime check with a compile-time guarantee,
removed the wrapper, and simplified everything downstream.

**When NOT to use `@MainActor`:**
- The module does heavy computation (image processing, large batch encoding)
- The module has no UI dependency (Logs, Trace)
- Making it `@MainActor` would force callers to `await` unnecessarily

---

## 2. Every `DispatchQueue` is a migration decision point

When you encounter a `DispatchQueue` during migration, don't keep it by
default. Evaluate whether it should become an actor, `@MainActor`, or stay
as-is.

### Decision tree

```
Is the queued work tied to UI / @MainActor types?
├── YES → Remove the queue, use @MainActor
│         (WebViewTracking: DDScriptMessageHandler)
└── NO
    Is the queued work lightweight and the queue just serialises access?
    ├── YES → Consider converting to an actor
    │         (protects mutable state with compiler guarantees)
    └── NO
        Is synchronous access required for correctness?
        ├── YES → Keep the queue / ReadWriteLock
        │         (DatadogLogs: SynchronizedAttributes needs
        │          synchronous snapshots on the user thread)
        └── NO
            Is the work CPU-intensive or blocking I/O?
            └── YES → Keep the queue or use Task with @concurrent
```

### Common patterns

| Before | After | When |
|--------|-------|------|
| `DispatchQueue` + `.async` in `@MainActor` class | Remove queue, run synchronously | Work is lightweight, class is already `@MainActor` |
| `DispatchQueue` serialising mutable state | `actor` | All callers can be `async` |
| `DispatchQueue` + `ReadWriteLock` | Keep as-is | Synchronous reads required for correctness |
| `DispatchQueue.global().async` for CPU work | `Task { @concurrent in }` | Heavy computation that shouldn't block caller |

### ReadWriteLock — modern alternatives

If synchronous access is required but `ReadWriteLock` feels too low-level:

| Option | Deployment target | Concurrent reads | `Sendable` without `@unchecked` |
|--------|-------------------|------------------|-------------------------------|
| `ReadWriteLock` (current) | Any | Yes | No (`@unchecked Sendable`) |
| `OSAllocatedUnfairLock<V>` | iOS 16+ | No (exclusive) | Yes |
| `Mutex<V>` (Synchronization) | iOS 18+ | No (exclusive) | Yes |
| `actor` | iOS 13+ | No (serialised) | Yes (compiler-enforced) |

Keep `ReadWriteLock` when concurrent reads are a performance concern (e.g.
attributes read on every log call). Consider `Mutex` when the deployment
target allows it and concurrent reads aren't measured as a bottleneck.

---

## 3. Callbacks are natural conversion points to `async/await`

Callback-based APIs (completion handlers, event mappers) are the most
impactful places to introduce structured concurrency. They convert deeply
nested, hard-to-follow closure chains into flat, linear `async` code.

### What to look for

| Pattern | Conversion |
|---------|------------|
| `func doWork(completion: @escaping (Result) -> Void)` | `func doWork() async throws -> Result` |
| `func map(event: T, callback: @escaping (T) -> Void)` | `func map(event: T) async -> T?` |
| `eventWriteContext { context, writer in }` | `let (context, writer) = await withCheckedContinuation { ... }` |
| Closure that "drops" events by not calling back | Return `nil` from `async -> T?` |

### Key rules

- **Mark converted protocols `Sendable`** — they're stored as properties and
  cross concurrency boundaries.
- **Synchronous conformers are fine** — a non-suspending `async` function
  just returns immediately. No overhead.
- **Thread-sensitive values** (`Date()`, `Thread.current`) must be captured
  in the **synchronous caller** before entering a `Task`, not inside the
  async method.

### Prepare/Write pattern for sync public API with async internals

When a synchronous public API (e.g. `log()`) needs to launch async work,
split the method into a synchronous **prepare** phase and an async **write** phase.
Use a struct to carry the captured state across the `Task` boundary:

```swift
private struct PreparedContext {
    let date: Date
    let threadName: String
    let tags: Set<String>
    let attributes: [String: AttributeValue]
    // ... all values that must be captured on the caller's thread
}

private func prepare(...) -> PreparedContext? {
    guard shouldProcess else { return nil }  // early exit before Task
    return PreparedContext(
        date: dateProvider.now,              // user thread
        threadName: Thread.current.dd.name,  // user thread
        tags: synchronizedTags.getTags(),    // snapshot before Task
        ...
    )
}

private func write(_ prepared: PreparedContext) async {
    // only async work here: eventWriteContext bridge, event creation, write
}

func log(...) {  // public, synchronous
    guard let prepared = prepare(...) else { return }
    Task { [weak self] in await self?.write(prepared) }
}
```

This guarantees that thread-sensitive values and mutable state snapshots are
captured at the exact moment of the public API call, not whenever the `Task`
starts executing.

---

## 4. `nonisolated(unsafe)` does NOT fix `sending` parameter errors

A common trap: when a `Task { }` closure captures a non-Sendable value, the
compiler reports *"Passing closure as a 'sending' parameter risks causing data
races."* It's tempting to suppress this with `nonisolated(unsafe)`:

```swift
// ❌ Does NOT work — nonisolated(unsafe) suppresses actor-isolation checks,
//    not `sending` parameter checks. These are two different compiler checks.
nonisolated(unsafe) let writer = writer
Task {
    writer.write(value: event)  // Still errors in Swift 6
}
```

**The fix is to make the captured type actually `Sendable`:**

```swift
// ✅ Make the protocol Sendable
public protocol Writer: Sendable { ... }

// Now the Task can capture it without issues
Task {
    writer.write(value: event)
}
```

| Compiler check | What it enforces | Suppressed by |
|----------------|------------------|---------------|
| Actor isolation | Value crosses actor boundary | `nonisolated(unsafe)` |
| `sending` parameter | Value captured by `Task.init` closure | Making the type `Sendable` |

---

## 5. Synchronous `flush()` is usually only needed for tests

The `Flushable` protocol (`func flush()` — blocks until pending work completes)
exists primarily to make tests deterministic. It synchronises with a background
`DispatchQueue` so assertions can run after async work finishes.

**When you remove the queue, `flush()` becomes dead code.**

If the work now runs synchronously (e.g. on `@MainActor`), there's no pending
async work to wait for. The `Flushable` conformance and any test-mock
counterparts can be removed entirely.

### Checklist before removing `flush()`

1. Search for all call sites of `flush()` across the codebase (including
   TestUtilities and integration tests)
2. Verify that the work previously done async is now synchronous
3. Remove the conformance from the production type
4. Remove the mock `flush()` method from test utilities
5. If tests used `flush()` + `waitForExpectations`, they likely work without
   both now — the expectations are fulfilled synchronously

---

## 6. `@MainActor` replaces `runOnMainThreadSync`

The SDK has a utility `runOnMainThreadSync { }` that dispatches work to the
main thread at runtime. In Swift 6, `@MainActor` provides the same guarantee
at **compile time**.

| Aspect | `runOnMainThreadSync` | `@MainActor` |
|--------|-----------------------|--------------|
| **When checked** | Runtime | Compile time |
| **Caller impact** | Any thread can call | Callers must be `@MainActor` or use `await` |
| **Safety** | Runtime crash if misused internally | Compiler error if misused |
| **Nesting** | Manual dispatch avoidance | Handled by the actor system |

Prefer `@MainActor` when the method interacts with `@MainActor` types
(WebKit, UIKit). Keep `runOnMainThreadSync` only if the method must remain
callable from a synchronous, non-isolated context without `await`.

---

## 7. Obj-C bridges can be `@MainActor`

`@objc` methods support `@MainActor`. When the underlying Swift API is
`@MainActor`, the Obj-C bridge should be too — it's the same thread
requirement, just expressed in a different language:

```swift
@objc
@MainActor
public static func enable(webView: WKWebView, ...) {
    WebViewTracking.enable(webView: webView, ...)
}
```

For `@objc` bridges that call `async` APIs, use `Task` + `DispatchSemaphore`
to block until the async work completes.

### Converting non-Sendable Obj-C types before `Task`

`@objc` parameters often use `Any` or `Error` which are not `Sendable`.
Convert them **before** creating the `Task`:

```swift
// Convert on the calling thread — before the Task boundary
let swiftAttributes = attributes.dd.swiftAttributes   // [String: Any] → [String: Encodable & Sendable]
let nsError = error.map { $0 as NSError }             // Error? → NSError? (@unchecked Sendable)

Task {
    await logger.critical(message: message, error: nsError, attributes: swiftAttributes)
}
```

| Obj-C type | Problem | Sendable conversion |
|------------|---------|---------------------|
| `[String: Any]` | `Any` is not `Sendable` | `.dd.swiftAttributes` wraps values in `AnyEncodable` (`@unchecked Sendable`) |
| `Error?` | `Error` is not `Sendable` | `error.map { $0 as NSError }` — `NSError` is `@unchecked Sendable` |
| `[Any]` | `Any` is not `Sendable` | Map to concrete `Sendable` types before the `Task` |

**Rule:** Never capture `[String: Any]` or raw `Error` across `Task` boundaries.

---

## 8. Test migration patterns

| Production change | Test change |
|-------------------|-------------|
| Method becomes `@MainActor` | Add `@MainActor` to the test class |
| Callback becomes `async -> T?` | Change test from `XCTestExpectation` to `async throws` |
| `flush()` removed | Remove `flush()` calls and mock; expectations are fulfilled synchronously |
| Type becomes `Sendable` | Usually no test change needed |

### `@MainActor` test classes

When production methods are `@MainActor`, annotate the entire test class:

```swift
@MainActor
class MyFeatureTests: XCTestCase {
    func testSomething() throws {
        // Can call @MainActor methods directly
    }
}
```

---

## 9. Module boundary: DatadogInternal stays Swift 5

`DatadogInternal` compiles in Swift 5 mode. Feature modules compile in
Swift 6 mode. This means:

- `Sendable` conformances added to `DatadogInternal` types are not enforced
  within `DatadogInternal` itself, but Swift 6 consumers rely on them.
- Use `@unchecked Sendable` in `DatadogInternal` for types with non-Sendable
  existentials (`Any`, protocol types), with a documented safety invariant.
- Protocol changes (e.g. `Writer: Sendable`) don't break Swift 5 conformers —
  enforcement kicks in only when they migrate to Swift 6.

---

## 10. General migration checklist

For each feature module:

1. **Set `.swiftLanguageMode(.v6)`** in `Package.swift` for the target
2. **Build and read the errors** — they tell you exactly what needs fixing
3. **Evaluate each `DispatchQueue`** — `@MainActor`, actor, or keep? (section 2)
4. **Convert callbacks to `async/await`** — event mappers, completion handlers (section 3)
5. **Watch for `sending` parameter errors** — make types `Sendable`, not `nonisolated(unsafe)` (section 4)
6. **Remove `Flushable` if the queue is gone** — no async work = nothing to flush (section 5)
7. **Replace `runOnMainThreadSync` with `@MainActor`** where applicable (section 6)
8. **Make types `Sendable`** where they cross isolation boundaries
9. **Update Obj-C bridges** — `@MainActor` or `Task` + semaphore; convert non-Sendable types first (section 7)
10. **Update tests** — `@MainActor` annotation, async throws, remove flush (section 8)
10. **Fix deployment targets** in `.xcodeproj` test targets to match `Package.swift`
11. **Write a module-specific `Resources/ModernConcurrency.md`** documenting decisions
