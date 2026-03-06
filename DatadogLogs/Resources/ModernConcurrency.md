# Modern Concurrency Migration Guide

Patterns and lessons learned from migrating `DatadogLogs` to Swift 6 with `async/await`.
Use this as a reference when applying the same migration to other feature modules
(e.g. `DatadogRUM`, `DatadogTrace`, `DatadogSessionReplay`).

---

## 1. Callback to async/await conversion

### Before (callback-based mapper)
```swift
public protocol LogEventMapper {
    func map(event: LogEvent, callback: @escaping (LogEvent) -> Void)
}
```

### After (async return)
```swift
public protocol LogEventMapper: Sendable {
    func map(event: LogEvent) async -> LogEvent?
}
```

**Key decisions:**
- The return type becomes `Optional` — returning `nil` means the event is dropped.
  This replaces the pattern of "not calling the callback" to drop events.
- The protocol must also conform to `Sendable` since mappers are stored as properties
  and cross concurrency boundaries.
- Internal synchronous conformers (like `SyncLogEventMapper`) simply return the
  value directly — the `async` is transparent for non-suspending implementations.

---

## 2. Bridging `eventWriteContext` to async with `withCheckedContinuation`

The core SDK provides `eventWriteContext { context, writer in }` which is a
**synchronous, escaping closure**. When the calling function is `async`, bridge
it using `withCheckedContinuation` to extract the context/writer pair:

```swift
private func internalLog(...) async {
    // All setup logic runs in the async context — no nested closures needed
    let tags = loggerTags.getTags()
    let combinedAttributes = ...

    // Bridge eventWriteContext → async
    let (context, writer) = await withCheckedContinuation { continuation in
        featureScope.eventWriteContext { context, writer in
            continuation.resume(returning: (context, writer))
        }
    }

    // Flat, linear async flow — no Task, no [weak self], no self. prefix
    var internalAttributes: [String: AttributeValue] = [:]
    if rumContextIntegration, let rum = context.additionalContext(ofType: RUMCoreContext.self) {
        internalAttributes[LogEvent.Attributes.RUM.applicationID] = rum.applicationID
    }

    guard let event = await builder.createLogEvent(...) else { return }
    writer.write(value: event)
}
```

**Benefits over the nested `Task`-inside-closure approach:**
- Flat, linear code — no nested closures or `self.` noise
- No inner `Task` needed — the outer async context handles the `await`
- Naturally awaitable — callers like `critical()` can `await` then call completion

**Important:** Thread-sensitive captures (`dateProvider.now`, `Thread.current.dd.name`)
must be captured in the **synchronous caller** before entering the `Task`:
```swift
func log(level: LogLevel, message: String, error: Error?, attributes: ...) {
    // on user thread:
    let date = dateProvider.now
    let threadName = Thread.current.dd.name
    Task { [weak self] in
        await self?.internalLog(date: date, threadName: threadName, ...)
    }
}
```

### For `MessageReceivers` (still uses the nested approach)

When the **protocol** requires a synchronous `receive(message:from:)` method,
you can't make the whole function async. In this case, the nested `Task`-inside-
`eventWriteContext` approach is still appropriate:

```swift
featureScope.eventWriteContext { context, writer in
    let builder = LogEventBuilder(...)
    Task {
        guard let event = await builder.createLogEvent(...) else { return }
        writer.write(value: event)
    }
}
```

---

## 3. Making types Sendable for `Task` capture

When you create a `Task { }` inside a closure, every value captured by the Task
must be `Sendable`. This is enforced by Swift 6's `sending` parameter on `Task.init`.

### What does NOT work
```swift
// ❌ nonisolated(unsafe) does NOT satisfy `sending` checks
nonisolated(unsafe) let writer = writer
Task {
    writer.write(value: event) // Still errors
}
```

`nonisolated(unsafe)` only suppresses **actor-isolation** checks, not **`sending`
parameter** checks. These are two different compiler checks in Swift 6.

### What works: make the types actually Sendable

The proper fix is to ensure captured types conform to `Sendable`:

| Type | Strategy | Rationale |
|------|----------|-----------|
| `DatadogContext` | `@unchecked Sendable` | Value type struct; `@unchecked` needed for `AdditionalContext` existential |
| `Writer` | `protocol Writer: Sendable` | Writers are designed for cross-thread use |
| `DDError` | Already `Sendable` | Struct with all `String` let properties |
| `LogMessage` | `Sendable` | Struct with all `let` properties; attributes use `Encodable & Sendable` |
| `AnyEncodable` | `@unchecked Sendable` | `@frozen` struct with `let value: Any`; immutable after creation |
| `CompletionHandler` | `@Sendable () -> Void` | Completions should be callable from any context |
| `[String: Encodable]` | Change to `[String: Encodable & Sendable]` | See section 4 |

### When to use `@unchecked Sendable`
- The type is a **value type** (struct/enum) with **immutable storage** (`let`)
- It contains existential types (`Any`, `AdditionalContext`, etc.) that can't
  conform to `Sendable` but are safe because the struct is immutable after creation
- Always document the safety invariant

---

## 4. Replacing `Encodable` with `Encodable & Sendable`

User-facing attribute dictionaries throughout the SDK use `[String: Encodable]`.
For Swift 6, change these to `[String: Encodable & Sendable]`.

**Root change** — update the `AttributeValue` typealias in `DatadogInternal`:
```swift
// Before
public typealias AttributeValue = Encodable

// After
public typealias AttributeValue = Encodable & Sendable
```

This propagates to all modules that use `AttributeValue` or `[AttributeKey: AttributeValue]`.

**Caveat:** Protocol compositions (`Encodable & Sendable`) are **non-nominal types**
and cannot be extended:
```swift
// ❌ Does not compile
extension AttributeValue { ... }
// Error: Non-nominal type 'AttributeValue' (aka 'Encodable & Sendable') cannot be extended

// ✅ Use the single protocol instead
extension Encodable {
    public var dd: DatadogExtension<any Encodable> { ... }
}
```

**Impact on the chain** — all these files need updating when changing attribute types:
- `SynchronizedAttributes` (storage + getters)
- `LoggerProtocol` / `InternalLoggerProtocol` (public API method signatures)
- `ConsoleLogger`, `RemoteLogger` (conformer implementations)
- `LogEventEncoder` (`LogEvent.Attributes` fields)
- `LogEventSanitizer` (sanitization functions)
- `LogMessage` (attribute fields in `DatadogInternal`)

Source-compatible for callers since common types (`String`, `Int`, `Bool`, `Date`,
`Array`, `Dictionary`, custom `Codable` structs) are all `Sendable`.

---

## 5. Test migration

### Before (XCTestExpectation + callback)
```swift
func testSomething() {
    let expectation = self.expectation(description: "...")
    builder.createLogEvent(...) { event in
        XCTAssertEqual(event.message, "expected")
        expectation.fulfill()
    }
    waitForExpectations(timeout: 1)
}
```

### After (async throws)
```swift
func testSomething() async throws {
    let event = try XCTUnwrap(
        await builder.createLogEvent(...)
    )
    XCTAssertEqual(event.message, "expected")
}
```

**Important:** `await` cannot be placed directly inside `XCTUnwrap(...)` in some
Xcode versions. If the compiler rejects it, split into two steps:
```swift
let event = await builder.createLogEvent(...)
let unwrapped = try XCTUnwrap(event)
```

---

## 6. ReadWriteLock vs Actor — when NOT to convert

Types like `SynchronizedAttributes` and `SynchronizedTags` use `ReadWriteLock`
for thread-safe state. It may be tempting to convert these to actors, but
**don't do it mechanically**. Always check the call sites first.

### Keep ReadWriteLock when:
- Callers need **synchronous access** for correctness (e.g. capturing a snapshot
  at the exact moment of a log call on the user thread)
- The type is already `Sendable` via its lock-based design
- Mutations are fire-and-forget — `await` adds overhead with no benefit

### Convert to actor when:
- All callers are already in an `async` context
- Synchronous reads are NOT required for correctness
- The type has complex state transitions that benefit from compiler-enforced isolation

**Example — why `SynchronizedAttributes` should stay as-is:**
```swift
// In RemoteLogger.internalLog — runs on the user thread
let tags = loggerTags.getTags()              // synchronous snapshot
let globalAttrs = globalAttributes.getAttributes()  // synchronous snapshot

featureScope.eventWriteContext { context, writer in
    // These snapshots reflect the exact moment of the log call.
    // If getTags()/getAttributes() were `await`, the snapshot would
    // be taken later, potentially with different values.
}
```

Converting to an actor would change `getTags()` to `await getTags()`, breaking
the guarantee that attributes/tags are captured at the caller's exact moment.

---

## 7. Obj-C bridge: async ↔ sync and Sendable conversions

`@objc` methods cannot be `async`. When an Obj-C bridge needs to call an async
API and block until it completes (e.g. flushing a critical log before a crash),
use `Task` + `DispatchSemaphore`:

```swift
@objc
public func _internal_sync_critical(message: String, error: Error?, attributes: [String: Any]) {
    guard let logger = sdkLogger as? InternalLoggerProtocol else { return }

    // 1. Convert non-Sendable Obj-C types BEFORE the Task:
    let swiftAttributes = attributes.dd.swiftAttributes   // [String: Any] → [String: Encodable & Sendable]
    let nsError = error.map { $0 as NSError }             // Error? → NSError? (@unchecked Sendable)

    // 2. Block the caller until the async work completes:
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        await logger.critical(message: message, error: nsError, attributes: swiftAttributes)
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + .seconds(2))     // safety timeout
}
```

### Why the semaphore?
Cross-platform SDKs (KMP, Flutter) call this during fatal crashes. They need
a **synchronous guarantee** that the log is persisted before the process exits.
The semaphore blocks the caller until the `Task` signals completion.

### Non-Sendable Obj-C types
`@objc` parameters often use `Any` or `Error` which are not `Sendable`:

| Obj-C type | Problem | Sendable conversion |
|------------|---------|---------------------|
| `[String: Any]` | `Any` is not `Sendable` | `.dd.swiftAttributes` → `[String: Encodable & Sendable]` (wraps in `AnyEncodable`) |
| `Error?` | `Error` is not `Sendable` | `error.map { $0 as NSError }` → `NSError?` (`@unchecked Sendable`) |

**Rule:** Always convert Obj-C parameters to `Sendable` equivalents *before*
creating the `Task`. Never capture `[String: Any]` or raw `Error` across `Task` boundaries.

---

## 8. Prepare/Write pattern for sync → async handoff

When a synchronous public API (`log()`) needs to launch async work, split the
method into a **synchronous prepare phase** and an **async write phase**:

```swift
private struct PreparedLogContext {
    let date: Date
    let threadName: String
    let tags: Set<String>
    let combinedAttributes: [String: AttributeValue]
    // ... all values captured on the user thread
}

// Phase 1: synchronous — runs on user thread
private func prepareLogContext(...) -> PreparedLogContext? {
    guard sampler.sample() else { return nil }
    let date = dateProvider.now              // must be user thread
    let threadName = Thread.current.dd.name  // must be user thread
    let tags = loggerTags.getTags()          // snapshot before Task
    // ...
    return PreparedLogContext(...)
}

// Phase 2: async — runs in cooperative thread pool
private func writeLog(_ prepared: PreparedLogContext) async {
    let (context, writer) = await withCheckedContinuation { ... }
    guard let event = await builder.createLogEvent(...) else { return }
    writer.write(value: event)
}

// Public API: prepare on caller thread, then hand off
func log(level: LogLevel, message: String, error: Error?, attributes: ...) {
    guard let prepared = prepareLogContext(...) else { return }
    Task { [weak self] in await self?.writeLog(prepared) }
}
```

**Why not capture everything in the async method?**
A `Task { }` may start on a different thread at a different time. Values like
`dateProvider.now`, `Thread.current.dd.name`, and mutable attribute snapshots
must be captured on the user thread *before* entering the `Task`, or you get
stale/wrong data.

---

## 9. Module boundary considerations

`DatadogInternal` compiles in **Swift 5 mode**. Feature modules like `DatadogLogs`
compile in **Swift 6 mode** (`.swiftLanguageMode(.v6)` in `Package.swift`).

This means:
- Sendable conformances added to `DatadogInternal` types won't be enforced by the
  compiler within `DatadogInternal` itself — but Swift 6 consumers WILL see and
  rely on them.
- Making `Writer: Sendable` at the protocol level doesn't break existing conformers
  in Swift 5 mode. They'll only need to satisfy the requirement when they migrate
  to Swift 6.
- Use `@unchecked Sendable` in `DatadogInternal` for types whose stored properties
  include non-Sendable existentials, with a `TODO` to remove it later.

---

## 10. Checklist for migrating another feature module

1. **Identify callback-based protocols** (event mappers, processors) → convert to `async -> T?`
2. **Mark converted protocols as `Sendable`**
3. **Update builders** that call the mapper → change return type to `async -> T?`
4. **Bridge `eventWriteContext` to async** — choose the right pattern:
   - **Owning method can be async** → use `withCheckedContinuation` to extract `(context, writer)`, then flat async flow (preferred)
   - **Owning method must stay sync** (protocol constraint) → nested `Task` inside `eventWriteContext` callback
5. **Capture thread-sensitive values on the user thread** — `dateProvider.now` and
   `Thread.current.dd.name` must be captured in the synchronous caller, then passed
   as parameters to the async method
6. **Ensure all Task-captured types are Sendable** — check `DatadogContext`, `Writer`,
   model types, attribute dictionaries
7. **Replace `[String: Encodable]` with `[String: Encodable & Sendable]`** in the module
8. **Convert tests** from `XCTestExpectation` to `async throws`
9. **Update mock types** in test targets to match new async signatures
10. **Run the compiler in Swift 6 mode** and fix any remaining `sending` parameter errors
