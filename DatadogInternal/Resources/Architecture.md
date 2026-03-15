# Architecture Review — Performance & Memory

Key findings from reviewing `DatadogInternal` and `DatadogCore` architecture,
focused on performance, memory, and concurrency efficiency.

---

## 1. DatadogContext — Frequent Copying of a Large Struct

`DatadogContext` is a struct with 30+ properties including nested structs, optionals,
dictionaries (`additionalContext: [String: AdditionalContext]`), and a growing array
inside `AppStateHistory`.

Every call to `contextProvider.read()` returns a full copy. This happens:
- On every `eventWriteContext()` call (once per RUM/Logs/Trace event)
- On every upload batch (per feature, per upload cycle)
- On every context message broadcast through the MessageBus

### Concern

The struct is value-typed but non-trivial to copy. The `applicationStateHistory`
property contains `snapshots: [Snapshot]` which triggers copy-on-write array
allocation when the context is modified after copying. With high event throughput
(e.g. RUM actions + resources + errors), this can generate measurable allocation
pressure.

### Suggestions

- **Measure copy cost**: Profile `DatadogContext` copy cost under realistic load.
  If significant, consider a reference-counted wrapper (e.g. `class ContextSnapshot`)
  to share immutable snapshots without copying.
- **Split hot and cold fields**: Properties that never change after init (`site`,
  `clientToken`, `service`, `env`, `sdkVersion`, `applicationName`,
  `applicationBundleIdentifier`, etc.) could live in a shared reference-counted
  struct. Only mutable fields (`serverTimeOffset`, `userInfo`, `batteryStatus`,
  `applicationStateHistory`, etc.) need copying.
- **Consider COW wrapper**: A copy-on-write box around the full context would
  amortize the cost — copies that are only read (the common case) share storage.

---

## 2. AppStateHistory.snapshots — Unbounded Growth

`AppStateHistory` accumulates a `Snapshot` for every app state transition
(foreground/background/inactive). The `snapshots` array is never pruned.

For long-lived apps (e.g. media players, navigation, kiosk mode), this array
grows indefinitely over the app's session. Since `AppStateHistory` is embedded
in `DatadogContext`, every copy of the context carries the full history.

### Suggestions

- **Cap the array**: Keep only the last N snapshots (e.g. 100). Older entries are
  only needed for `foregroundDuration(during:)` and `state(at:)` queries, which
  typically look at recent time ranges.
- **Prune on read**: When appending a new state, remove snapshots older than a
  configurable threshold (e.g. 1 hour).
- **Separate from context**: Store `AppStateHistory` outside `DatadogContext`
  (e.g. in the `DatadogContextProvider` actor) and query it on demand rather than
  copying it into every context snapshot.

---

## 3. FileReader.filesRead — Unbounded Set Growth

`FileReader` maintains `filesRead: Set<String>` that records every file name
passed to `markBatchAsRead`. This Set is never pruned. Since file names are
timestamp-based strings, the Set grows monotonically over the app's lifetime.

In apps that run continuously and generate many events (e.g. IoT dashboards),
this Set can accumulate thousands of entries, consuming memory and slowing
`contains` checks (though `Set` lookup is O(1), the string hashing has a cost
proportional to the total number of stored strings due to hash table resizing).

### Suggestions

- **Prune after each upload cycle**: Once a file has been deleted from disk,
  remove its name from `filesRead`. The file no longer exists, so excluding it
  from future reads is unnecessary.
- **Use a bounded FIFO set**: Cap at the last N entries (e.g. 1000). Files are
  read oldest-first, so old entries are irrelevant once the batch window moves.

---

## 4. Concurrency Pattern Fragmentation

The codebase uses four distinct synchronization mechanisms:

| Pattern | Count | Use case |
|---------|-------|----------|
| Actors | 7 | MessageBus, FilesOrchestrator, FeatureStorage, FeatureDataStore, DatadogContextProvider, DataUploadWorker, NetworkInstrumentationFeature |
| NSLock | 8+ | Swizzlers, FeatureStore, NetworkInstrumentationFeature (lock-protected properties), ViewHitchesReader, Monitor |
| @ReadWriteLock (pthread_rwlock) | 5 | NetworkContextProvider, CoreRegistry, ContextSharingTransformer, BackgroundTaskCoordinator |
| @unchecked Sendable | 28 | Various types with manual thread-safety guarantees |

### Concern

- **@ReadWriteLock heap allocation**: Each `ReadWriteLock` allocates a
  `pthread_rwlock_t` on the heap (`.allocate(capacity: 1)`). For a property
  wrapper used on many properties, this is one heap allocation per wrapped
  property. `NSLock` is lighter (Foundation object, single allocation).
- **Reader-writer lock overhead**: `pthread_rwlock` is designed for
  read-heavy/write-rare workloads. For the current usage patterns (most
  properties are read and written in roughly equal proportion), a simple
  `NSLock` or `os_unfair_lock` would have lower overhead due to simpler
  lock/unlock paths.
- **Mixed patterns complicate reasoning**: Having three lock types plus actors
  makes it harder to verify correctness and to onboard new contributors.

### Suggestions

- **Standardize on NSLock for non-actor state**: Replace `@ReadWriteLock` with
  `NSLock` where the read/write ratio doesn't justify reader-writer semantics.
  This eliminates `pthread_rwlock_t` heap allocations and simplifies the API.
- **Evaluate `os.Mutex`**: When dropping iOS 15 support, Swift's `Mutex` (iOS
  18+) provides a compiler-verified, non-copyable lock with lower overhead
  than `NSLock`.
- **Track @unchecked Sendable debt**: The 28 `@unchecked Sendable` types
  represent deferred concurrency verification. Each should have a comment or
  tracking issue explaining why it's needed and when it can be removed.

---

## 5. FileWriter — No Backpressure on AsyncStream

`FileWriter` uses `AsyncStream<Data>.makeStream()` with default buffering
(unlimited). Each `write(value:)` call encodes synchronously and yields the
`Data` to the stream. The drain `Task` consumes sequentially.

If the producer (event encoding) outpaces the consumer (file I/O), the stream's
buffer grows unboundedly in memory. Under burst traffic (e.g. hundreds of RUM
errors in rapid succession), this could spike memory.

### Suggestions

- **Add a bounded buffer**: Use `AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(N))`
  or `.bufferingOldest(N)` to cap the in-flight event count.
- **Apply backpressure**: Consider using `AsyncChannel` (from swift-async-algorithms)
  or a bounded `AsyncStream` that blocks the producer when the buffer is full.
  This would naturally throttle event encoding during bursts.

---

## 6. Directory Scanning in FilesOrchestrator

`purgeFilesDirectoryIfNeeded()` loads all files and their sizes from the
directory every time a new writable file is created. `Directory.files()` returns
an unsorted array of all files, which is then sorted.

### Concern

For features with many small batches (e.g. RUM with high event rate), the
directory can accumulate dozens of files between upload cycles. Scanning and
sorting the full directory on every new file creation adds overhead.

### Suggestions

- **Cache file metadata**: Maintain an in-memory index of file names and sizes,
  updated incrementally on create/delete. Only fall back to full directory scan
  on startup or after errors.
- **Lazy purge**: Instead of checking on every new file, purge on a timer or
  after every N files created.

---

## 7. Monitor Command Processing — Lost FIFO Ordering

`Monitor.process(command:)` creates a new `Task` for each command. After
`await eventWriteContext()`, Tasks resume in non-deterministic order. An `NSLock`
was added to prevent concurrent scope access, but **command ordering is not
guaranteed** — a command submitted second may process before the first.

This is a behavioral change from the pre-migration serial queue approach, where
commands were always processed in FIFO order.

### Suggestion

See `TODO.md` Phase 9: Convert `Monitor` to an actor with `AsyncStream`-based
command pipeline. The `for await` loop guarantees FIFO ordering and eliminates
the need for the lock.

---

## 8. Tuple Typealiases vs Structs

Several types are defined as tuple typealiases:

| Typealias | Module | Definition |
|-----------|--------|------------|
| `Hitch` | DatadogRUM | `(start: Int64, duration: Int64)` |
| `HitchesConfiguration` | DatadogRUM | `(maxCollectedHitches: Int, acceptableLatency: TimeInterval, hangThreshold: TimeInterval)` |
| `HitchesDataModel` | DatadogRUM | `(hitches: [Hitch], hitchesDuration: Double)` |
| `KronosAnnotatedTime` | DatadogCore | `(date: Date, timeSinceLastNtpSync: TimeInterval)` |

### Concern

- Tuples cannot conform to protocols (`Sendable`, `Equatable`, `Codable`)
- Tuples are not extensible (can't add computed properties or methods)
- Tuples prevent future optimizations like `@frozen` or `@inlinable`
- Nested tuple arrays (e.g. `[Hitch]`) have the same memory layout as
  `[(Int64, Int64)]`, which is fine, but lose type safety

### Suggestion

Replace tuple typealiases with small structs. This enables `Sendable`
conformance (important for the concurrency migration), `Equatable` for
testing, and room for future extensions.

---

## 9. ReadWriteLock — pthread_rwlock_t Heap Allocation

`ReadWriteLock<Value>` allocates `pthread_rwlock_t` via `UnsafeMutablePointer.allocate(capacity: 1)`.
This is a manual heap allocation + deallocation cycle for every instance.

With 5 active usages, this is 5 heap allocations that persist for the SDK lifetime.
While not a major cost, it's unnecessary overhead given that `NSLock` achieves
equivalent performance for the actual usage patterns (no concurrent reader
benefit observed).

### Suggestion

When all `@ReadWriteLock` usages are replaced by `NSLock` or actors (as part of
the ongoing migration), remove the `ReadWriteLock` type entirely. This
eliminates the `pthread_rwlock_t` unsafe pointer management and simplifies the
concurrency model.

---

## Summary

| # | Finding | Severity | Effort |
|---|---------|----------|--------|
| 1 | `DatadogContext` copied frequently with nested collections | Medium | Medium |
| 2 | `AppStateHistory.snapshots` grows unbounded | Medium | Low |
| 3 | `FileReader.filesRead` Set grows unbounded | Low | Low |
| 4 | Mixed concurrency patterns (4 mechanisms) | Low | High (ongoing migration) |
| 5 | `FileWriter` AsyncStream has no backpressure | Low | Low |
| 6 | Full directory scan on each new file | Low | Medium |
| 7 | Command ordering lost in Monitor | Medium | Medium (Phase 9) |
| 8 | Tuple typealiases prevent Sendable conformance | Low | Low |
| 9 | ReadWriteLock uses unsafe heap allocation | Low | Low (remove after migration) |
