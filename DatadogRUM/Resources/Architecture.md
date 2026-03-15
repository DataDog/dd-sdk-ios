# DatadogRUM — Architecture & Performance Notes

This document captures key architectural observations about the RUM module,
with a focus on performance, memory, and concurrency characteristics.

## Command Processing Pipeline

```
┌──────────────┐    AsyncStream     ┌──────────────┐    Scope Tree     ┌────────────┐
│  Public API  │ ──────────────────▶│   Monitor    │ ────────────────▶ │  Scopes    │
│  (any thread)│    (RUMCommand)    │  (for await) │   (synchronous)   │  (process) │
└──────────────┘                    └──────────────┘                   └────────────┘
                                                                            │
                                                                    writer.write()
                                                                            │
                                                                            ▼
                                                                    ┌────────────┐
                                                                    │ FileWriter │
                                                                    │ AsyncStream│
                                                                    │  (Data)    │
                                                                    └────────────┘
```

All RUM commands flow through a single `AsyncStream` in `Monitor`. The
`for await` loop processes each command sequentially through the scope tree.
This guarantees ordering and avoids races in the state machine — but it also
means **a slow command blocks all subsequent commands**.

### Scope tree structure

```
RUMApplicationScope
 └── RUMSessionScope
      └── RUMViewScope
           ├── RUMResourceScope (0..n)
           ├── RUMUserActionScope (0..n)
           ├── RUMLongTaskScope
           └── ViewHitchesReader
```

Each `process(command:context:writer:)` call traverses the full tree.
Within `RUMViewScope`, all child scopes are iterated via `compactMap`:

```swift
resourceScopes = resourceScopes.compactMap { $0.process(...) ? $0 : nil }
```

For a view with many concurrent resources, every incoming command iterates
all sibling resource scopes. Most commands are irrelevant to most siblings.

### Writer pipeline

`Writer.write(value:)` is synchronous at the call site:
1. **Encoding** (JSON) happens on the caller thread (the Monitor's `for await` loop)
2. The encoded `Data` is enqueued into `FileWriter`'s internal `AsyncStream`
3. File I/O is dispatched to the orchestrator actor

This means JSON encoding of complex RUM events blocks the command stream.

## Concurrency Model

### What runs where

| Component | Execution context | Synchronization |
|-----------|------------------|-----------------|
| Monitor `for await` loop | Cooperative thread pool (single task) | Sequential by design |
| Scope tree processing | Same task as Monitor | None needed (single-threaded) |
| `TelemetryReceiver` | Actor isolation | Actor serial executor |
| `WebViewEventReceiver` | Actor isolation | Actor serial executor |
| `ViewHitchesReader` | CADisplayLink (main thread) + scope reads | `NSLock` |
| `VitalRefreshRateReader` | CADisplayLink (main thread) | None (unsynchronized) |
| `AccessibilityReader` | NotificationCenter (main queue) | `@ReadWriteLock` |
| `ValuePublisher` | Any thread | `DispatchQueue` (concurrent + barrier) |
| `AppHangsWatchdogThread` | Dedicated `Thread` | `ReadWriteLock` (intentional) |
| `SessionEndedMetricController` | Scope processing | `@ReadWriteLock` |
| `FatalErrorContextNotifier` | Scope processing | `@ReadWriteLock` |

### Why most components cannot be actors

The scope processing model is synchronous: `RUMScope.process(command:context:writer:) -> Bool`.
Any component accessed from within scope processing must provide **synchronous** reads and writes.
This rules out actor isolation for:

- `SessionEndedMetricController` — called from every scope on every event
- `WatchdogTerminationMonitor` — `update(viewEvent:)` called from `RUMViewScope`
- `AccessibilityReader` — `state` read from `RUMViewScope`
- `FatalErrorContextNotifier` — updated from scope processing
- `ViewCache` — read from scope processing

Actor isolation requires `await`, which would cascade into making `process()` async —
a fundamental change to the scope tree model.

### Fire-and-forget Tasks

Receivers implementing `FeatureMessageReceiver.receive(message:)` (synchronous protocol)
use `Task { ... }` to bridge to async APIs like `featureScope.eventWriteContext()`.
This is the correct pattern given the synchronous protocol constraint. These tasks
handle infrequent events (crashes, telemetry, web view events) where the allocation
cost is negligible compared to the disk I/O they trigger.

## Performance Considerations

### 1. JSON encoding on the critical path

**Impact**: Medium-High (CPU)

`RUMViewEvent` is a large, deeply nested `Codable` type. Encoding it to JSON
blocks the Monitor's `for await` loop, delaying processing of subsequent commands.
View update events are frequent — they fire after every action, error, and resource.

**Possible improvement**: Move encoding to the `FileWriter`'s drain loop. Instead
of `AsyncStream<Data>`, the stream would carry `Encodable` values and encode them
off the command processing thread. Ordering is preserved by FIFO semantics. The
tradeoff is slightly higher memory pressure (values retained until encoded).

### 2. Full `RUMViewEvent` copy in crash context

**Impact**: Medium (Memory + CPU)

`FatalErrorContextNotifier.view` stores a full copy of the last `RUMViewEvent`
on every view update. It then serializes this to the message bus for crash context.
This happens on the scope processing thread.

**Possible improvement**: Store only the fields needed for crash reconstruction
(view ID, session ID, timestamps, error/action counts) instead of the full event.
This reduces both the struct copy cost and serialization overhead.

### 3. `@ReadWriteLock` overhead for single-reader patterns

**Impact**: Low-Medium (CPU)

`@ReadWriteLock` wraps `pthread_rwlock_t`, which maintains reader count tracking.
This has higher overhead than `os_unfair_lock` / `NSLock` even for read acquisitions.
The read-write distinction only pays off with many concurrent readers and rare writers.

Most current usages are single-reader:
- `SessionEndedMetricController` — scope processing thread
- `WatchdogTerminationMonitor` — one Task writer, one receiver reader
- `ViewCache` — scope processing + WebView receiver

For these, `NSLock` would be faster. The per-call difference is small (~tens of
nanoseconds), but `SessionEndedMetricController` and `ViewCache` are called on
every view event.

### 4. `ValuePublisher` creates GCD blocks at frame rate

**Impact**: Low-Medium (CPU + allocations)

`VitalRefreshRateReader.didUpdateFrame` calls `valuePublisher.mutateAsync { ... }`
at 60–120 Hz. Each call dispatches a barrier block to a `DispatchQueue` — that's
60–120 GCD block allocations per second per vital publisher.

Since `didUpdateFrame` runs on the main thread (CADisplayLink) and the values
are only read from scope processing, the concurrent queue + barrier pattern is
overkill. Direct mutation with `NSLock` (like `ViewHitchesReader`) would eliminate
GCD block allocations entirely.

### 5. Scope tree traversal is O(n) for sibling scopes

**Impact**: Low (CPU)

Within `RUMViewScope`, each command iterates all child resource scopes and action
scopes. For a view with 20 concurrent network requests, every command scans all 20.
Most commands target a specific resource (matched by ID) and are irrelevant to siblings.

A dictionary keyed by resource/action ID would make targeted dispatch O(1).
However, the current approach is simple and the n is typically small (< 20).

## Memory Profile

| Component | What it holds | Bounded? |
|-----------|--------------|----------|
| `ViewHitchesReader` | Up to 1,000 hitches (16 bytes each = ~16 KB) | Yes (hard cap + purge) |
| `ViewCache` | Up to 30 view IDs with 3-minute TTL | Yes (capacity + TTL) |
| `SessionEndedMetricController` | One `SessionEndedMetric` per active session | Yes (typically 1 session) |
| `FatalErrorContextNotifier` | Full `RUMViewEvent` + session state + global attributes | No explicit bound |
| Scope tree | One scope per active view/resource/action | Bounded by app behavior |
| `ValuePublisher` | Running statistics (min/max/avg/count) | Yes (fixed size) |
| `FileWriter` `AsyncStream` | Encoded `Data` buffers pending disk write | Bounded by stream buffer policy |

## What Should NOT Change

- **Monitor's `AsyncStream` command channel**: Sequential processing is correct for
  a state machine. Parallelizing scope processing would introduce races.
- **`NSLock` in `ViewHitchesReader`**: Already the right primitive for synchronous
  60–120 Hz callbacks.
- **`AppHangsWatchdogThread` as raw `Thread`**: Must run outside the cooperative
  thread pool to detect hangs that would block actors and Tasks.
- **Fire-and-forget Tasks in receivers**: Correct pattern for bridging synchronous
  protocol methods to async APIs. The events are infrequent.
- **Synchronous `RUMScope.process()`**: Making it async would fundamentally change
  the state machine model with no clear benefit — the scope tree must process
  commands sequentially regardless.
