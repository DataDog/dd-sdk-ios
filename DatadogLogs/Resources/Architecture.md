# DatadogLogs — Architecture & Performance Analysis

## 1. Event Lifecycle

A log event travels through the following stages from a public API call to disk:

```
logger.info("message", attributes: [...])
│
├─ 1. LoggerProtocol.info()                     [user thread, sync]
│     Convenience method → delegates to log(level:message:error:attributes:)
│
├─ 2. RemoteLogger.log()                        [user thread, sync]
│     Calls prepareLogContext() to snapshot state
│
├─ 3. prepareLogContext()                       [user thread, sync]
│     ├─ sampler.sample() → early exit if dropped
│     ├─ threshold check → early exit if below threshold
│     ├─ dateProvider.now
│     ├─ Thread.current.dd.name
│     ├─ loggerTags.getTags()           → ReadWriteLock read, returns COPY
│     ├─ globalAttributes.getAttributes() → ReadWriteLock read, returns COPY
│     ├─ loggerAttributes.getAttributes() → ReadWriteLock read, returns COPY
│     ├─ merge logger + log attributes  → new dictionary
│     ├─ merge global + user attributes → new dictionary
│     └─ builds PreparedLogContext struct
│
├─ 4. Task { await writeLog(prepared) }         [cooperative thread pool]
│     New Task allocated per log call
│
├─ 5. writeLog()                                [cooperative thread pool, async]
│     ├─ await featureScope.eventWriteContext()  → (DatadogContext, Writer)
│     ├─ build internalAttributes (RUM/Trace context lookups)
│     ├─ optionally generate backtrace for binary images
│     ├─ LogEventBuilder.createLogEvent()       → builds LogEvent struct
│     │     └─ if eventMapper != nil: await eventMapper.map(event:)
│     ├─ writer.write(value: log)               → triggers encoding
│     │     ├─ LogEventSanitizer().sanitize()    → new sanitizer, copies attributes/tags
│     │     └─ LogEventEncoder().encode()        → new encoder, JSON serialization
│     └─ if error/critical: featureScope.send(message: RUMErrorMessage)
│
└─ 6. FileWriter drain                          [background, async]
      Encoded data queued → written to disk
```

## 2. Performance Findings

### 2.1 Task-per-log allocation — HIGH impact

**Where:** `RemoteLogger.log()` L159–162, `InternalLoggerProtocol.log()` L272–274

Every call to `logger.info()`, `logger.error()`, etc. spawns a new unstructured `Task`:

```swift
Task { [weak self] in
    await self?.writeLog(prepared)
}
```

Each `Task` carries:
- Runtime allocation for the task object and its executor record
- A `[weak self]` capture context (closure heap allocation)
- Scheduling overhead in the cooperative thread pool

Under burst logging (100+ logs/sec), this creates significant allocation pressure. The `critical()` path avoids this since it is `async` itself and calls `writeLog` directly.

**Suggestion:** Replace the per-log `Task` with a shared log channel. An `AsyncStream<PreparedLogContext>` consumed by a single long-lived `Task` would amortize the scheduling cost across all logs. Alternatively, a serial `DispatchQueue` with a drain loop avoids the cooperative pool entirely.

---

### 2.2 Triple dictionary copy in prepareLogContext — MEDIUM impact

**Where:** `RemoteLogger.prepareLogContext()` L129–140

Each log call performs three lock-protected reads, each returning a full copy:

```swift
let tags = loggerTags.getTags()                    // copy 1: Set<String>
let globalAttributes = globalAttributes.getAttributes()  // copy 2: [String: AV]
let loggerAttributes = loggerAttributes.getAttributes()  // copy 3: [String: AV]
```

Then two merges that each allocate a new dictionary:

```swift
let userAttributes = loggerAttributes.merging(logAttributes ?? [:]) { $1 }   // copy 4
let combinedAttributes = globalAttributes.merging(userAttributes) { $1 }     // copy 5
```

For an app with 10 global attributes + 5 logger attributes + 2 log-level attributes, this is 5 dictionary/set allocations per log, most of which are immediately discarded.

**Suggestion:** Consider a single-pass merge that builds the final dictionary directly:

```swift
var combined = globalAttributes.getAttributes()          // one copy
loggerAttributes.mergeInto(&combined)                    // mutate in-place
if let logAttrs = attributes { combined.merge(logAttrs) { _, new in new } }
```

This reduces 5 allocations to 2 (one for the initial copy, one for the in-place result). A custom `mergeInto` method on `SynchronizedAttributes` could read the lock and merge directly into the target dictionary without an intermediate copy.

---

### 2.3 Sanitizer and Encoder instantiation per encode — MEDIUM impact

**Where:** `LogEvent.encode(to:)` L158–161

```swift
public func encode(to encoder: Encoder) throws {
    let sanitizedLog = LogEventSanitizer().sanitize(log: self)
    try LogEventEncoder().encode(sanitizedLog, to: encoder)
}
```

Both `LogEventSanitizer` and `LogEventEncoder` are stateless structs. Creating them per call is cheap, but `sanitize(log:)` performs significant work:

- `removeInvalidAttributes` → `filter` → new dictionary
- `removeReservedAttributes` → `filter` → new dictionary  
- `sanitizeKeys` → `map` + `Dictionary(uniqueKeysWithValues:)` → new dictionary
- `limitNumberOf` → `dropLast` + `Dictionary(uniqueKeysWithValues:)` → new dictionary
- Tag sanitization: 5 chained `map`/`filter` operations → 5 intermediate arrays

For the common case where all attributes are valid (no empty keys, no reserved names, no illegal characters), these filters allocate new collections only to return identical content.

**Suggestion:** Add early exits to avoid allocations when sanitization is a no-op:

```swift
private func removeInvalidAttributes(_ attributes: [String: AV]) -> [String: AV] {
    if attributes.keys.allSatisfy({ !$0.isEmpty }) { return attributes }
    return attributes.filter { !$0.key.isEmpty }
}
```

For tags, chain operations on a single mutable array instead of creating 5 intermediate arrays:

```swift
private func sanitize(tags: [String]?) -> [String]? {
    guard var tags = tags else { return nil }
    tags = tags.compactMap { tag in
        let lowered = tag.lowercased()
        guard startsWithAllowedCharacter(tag: lowered) else { return nil }
        var sanitized = replaceIllegalCharactersIn(tag: lowered)
        sanitized = removeTrailingCommasIn(tag: sanitized)
        sanitized = limitToMaxLength(tag: sanitized)
        guard isNotReserved(tag: sanitized) else { return nil }
        return sanitized
    }
    return limitToMaxNumberOfTags(tags)
}
```

---

### 2.4 LogEvent is a large struct — MEDIUM impact

**Where:** `LogEventBuilder.createLogEvent()` L57–92

`LogEvent` contains 20+ stored properties including nested structs (`Device`, `OperatingSystem`, `UserInfo`, `AccountInfo`, `Attributes`, `Error`). As a value type, every assignment or function argument pass copies the entire struct.

In the current flow, a `LogEvent` is:
1. Created in `createLogEvent()` → 1st copy
2. Potentially passed to `eventMapper.map(event:)` → 2nd copy (argument)
3. Returned from `createLogEvent()` → 3rd copy (return)
4. Passed to `writer.write(value:)` → 4th copy
5. Copied in `sanitize(log:)` → 5th copy (`var sanitizedLog = log`)

Swift's optimizer can elide some of these copies, but not all (especially across `async` boundaries).

**Suggestion:** This is inherent to the value-type design and shouldn't be changed lightly — value semantics provide thread safety. However, two mitigations exist:
- Make `LogEvent` a class (reference type) if profiling shows copy overhead dominates
- Move sanitization into the builder (before the event leaves `createLogEvent`), eliminating the extra copy in `encode(to:)`

---

### 2.5 createLogEvent is async even without a mapper — LOW impact

**Where:** `LogEventBuilder.createLogEvent()` L45–98

The method is `async` because of the `eventMapper?.map(event:)` call. When `eventMapper` is `nil` (the common case), no suspension occurs, but callers still pay for the async function prologue/epilogue.

**Suggestion:** Split into sync and async paths:

```swift
func createLogEvent(...) -> LogEvent? {
    let log = LogEvent(...)
    // no mapper → return immediately without async overhead
    return log
}

func createLogEvent(...) async -> LogEvent? {
    let log = LogEvent(...)
    return await eventMapper?.map(event: log) ?? log
}
```

The caller can check `configuration.eventMapper == nil` and call the sync overload. This avoids async machinery for every log on the hot path.

---

### 2.6 Tags encoding — repeated String work — LOW impact

**Where:** `LogEventEncoder.encode()` L364–371

```swift
var tags = log.tags ?? []
tags.append(log.ddTags)
let tagsString = tags.joined(separator: ",")
```

`log.ddTags` is already a comma-separated string. Appending it to an array and then joining everything re-parses work that was already done. Minor, but avoidable.

**Suggestion:** Build the final string directly:

```swift
if let tags = log.tags, !tags.isEmpty {
    let tagsString = tags.joined(separator: ",") + "," + log.ddTags
    try container.encode(tagsString, forKey: .tags)
} else {
    try container.encode(log.ddTags, forKey: .tags)
}
```

---

### 2.7 ReadWriteLock contention under concurrent logging — LOW impact

**Where:** `SynchronizedAttributes.getAttributes()`, `SynchronizedTags.getTags()`

`prepareLogContext` acquires three read locks sequentially. Under high concurrency with frequent attribute mutations, writers can starve readers or vice versa. The `pthread_rwlock` implementation favors writers on most platforms.

**Current design is correct** — `ReadWriteLock` provides the right semantics (concurrent reads, exclusive writes) for this access pattern. The contention is theoretical unless profiled.

**Suggestion:** Monitor under load. If contention appears, consider `os_unfair_lock` (lower overhead, no reader/writer distinction) or `OSAllocatedUnfairLock` (Swift 5.9+). These trade concurrent-read capability for lower per-acquisition cost, which is often a net win when locks are held briefly.

---

## 3. What is Well-Designed (Do NOT Change)

### 3.1 Synchronous preparation on the user thread

`prepareLogContext()` captures `Date`, `Thread.current.dd.name`, tags, and attributes on the caller's thread before any async handoff. This guarantees timing accuracy and correct thread attribution.

### 3.2 Early exits before preparation

```swift
guard configuration.sampler.sample() else { return nil }
guard level.rawValue >= configuration.threshold.rawValue else { return nil }
```

Dropped logs incur near-zero cost — no allocations, no lock acquisitions, no Task creation.

### 3.3 Separation of PreparedLogContext and writeLog

The Prepare/Write pattern cleanly separates what must run synchronously (user-thread state) from what can run asynchronously (context fetch, building, encoding, I/O). This is the correct architecture for an async logging pipeline.

### 3.4 critical() as a direct async call

`critical()` is `async` and calls `writeLog()` directly (no `Task` wrapper). This ensures the caller can `await` completion before a crash handler terminates the process — essential for crash-time logging.

### 3.5 ConsoleLogger simplicity

`ConsoleLogger` is fully synchronous, does no encoding, and has no-op attribute/tag methods. Zero overhead for what is a development-only tool.

### 3.6 LogsFeature as a struct

`LogsFeature` is a value type with no mutable state. The shared `SynchronizedAttributes` is the only mutable component, and it is properly synchronized. This avoids reference-counting overhead for the feature itself.

### 3.7 FileWriter buffering

The encoding → `AsyncStream` → disk drain pipeline keeps encoding predictable and non-blocking. The caller never waits for I/O.

---

## 4. Summary — Impact Matrix

| Finding | Impact | Effort | Recommendation |
|---------|--------|--------|----------------|
| Task-per-log | High | Medium | Replace with shared log channel |
| Triple dictionary copy + 2 merges | Medium | Low | Single-pass merge |
| Sanitizer allocations (no-op case) | Medium | Low | Early exits for common case |
| LogEvent copy chain | Medium | High | Profile first; consider class if proven |
| async without mapper | Low | Low | Sync overload for no-mapper path |
| Tags encoding | Low | Low | Direct string concatenation |
| ReadWriteLock contention | Low | Medium | Profile first; swap lock type if needed |

---

## 5. Architectural Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                          User Thread                                │
│                                                                     │
│  logger.info("msg", attributes: [...])                              │
│       │                                                             │
│       ▼                                                             │
│  ┌──────────────────────────────────────────────┐                   │
│  │ prepareLogContext()                          │                   │
│  │  ├─ sampler/threshold guard (early exit)     │                   │
│  │  ├─ capture date, thread name                │                   │
│  │  ├─ snapshot tags & attributes (3 lock reads)│                   │
│  │  ├─ merge dictionaries (2 copies)            │                   │
│  │  └─ → PreparedLogContext                     │                   │
│  └──────────────────────────────────────────────┘                   │
│       │                                                             │
│       │  Task { }                                                   │
└───────┼─────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     Cooperative Thread Pool                          │
│                                                                     │
│  ┌──────────────────────────────────────────────┐                   │
│  │ writeLog(prepared)                           │                   │
│  │  ├─ await eventWriteContext() → (ctx, writer)│                   │
│  │  ├─ build internalAttributes (RUM/Trace)     │                   │
│  │  ├─ LogEventBuilder.createLogEvent()         │                   │
│  │  │    └─ await eventMapper?.map() (if set)   │                   │
│  │  ├─ writer.write(value: log)                 │                   │
│  │  │    ├─ LogEventSanitizer().sanitize()       │                   │
│  │  │    └─ LogEventEncoder().encode() → JSON   │                   │
│  │  └─ if error/critical: send RUMErrorMessage  │                   │
│  └──────────────────────────────────────────────┘                   │
│       │                                                             │
│       ▼                                                             │
│  ┌──────────────────────────────────────────────┐                   │
│  │ FileWriter                                   │                   │
│  │  └─ AsyncStream drain → write to disk        │                   │
│  └──────────────────────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────────────┘
```
