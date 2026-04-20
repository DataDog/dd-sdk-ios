# Plan 4 — iOS SDK Integration

**Branch:** `feature/timeseries`
**Scope:** Wire the timeseries pipeline into `DatadogRUM` so real memory and CPU samples flow through the SDK's upload infrastructure.

---

## Context

The standalone `DatadogTimeseries` package (Plan 1 + 3) is complete and committed. It has:
- `Sample`, `TimeseriesEvent`, `TimeseriesConfig`, `TimeseriesName`
- `TimeseriesPipeline` with `processAll()` (batch/CSV mode)
- `SampleFilter` protocol + PassThrough / Deadband / Window implementations
- Current schema: `{ "data_point_value": 42.0 }` (Schema B)

`DatadogRUM` already has (on `feature/timeseries` / develop):
- `VitalMemoryReader` — reads `phys_footprint` via `task_info()`
- `VitalCPUReader` — reads CPU ticks via `host_statistics()`
- `VitalInfoSampler` — timer-driven, aggregates vitals stats for RUM view events
- `RUMScopeDependencies.vitalsReaders: VitalsReaders?`
- `RUMSessionScope` — session lifecycle hook point
- `RUMFeature` — initialises `VitalsReaders` from `vitalsUpdateFrequency` config

Marie's prototype (`feature/timeseries-prototype`) implements `MemoryTimeseriesCollector` as reference — single metric, Schema B, batch size 5, tied to `RUMSessionScope`. We follow the same pattern for both metrics with Schema C.

---

## Decisions

- **Schema C** — DataPoint is `{ "timestamp": ..., "data_point": { "memory_max": ..., "memory_percent": ... } }`. Nested `data_point` object with named metric fields. Static `CodingKeys` — compatible with code generation.
- **Two generated event types** — `RUMTimeseriesMemoryEvent` and `RUMTimeseriesCPUEvent` defined separately in rum-events-format, each with their own `DataPoint` struct.
- **memory_percent computed at sampling time** — `VitalMemoryReader` returns bytes; collector divides by `ProcessInfo.processInfo.physicalMemory * 100` to get percent.
- **No cross-package import** — `DatadogRUM` does not import `DatadogTimeseries`. Standalone package stays for demo/runner use only.
- **PassThrough filter only** — no sampling for this integration. Deadband/Window deferred.
- **Batch size: 30** — ~30 seconds of data per event.
- **Sampling interval: 1s** — dedicated `DispatchSourceTimer` (not reusing `VitalInfoSampler`, which runs at user-configured frequency).
- **Collector lifetime: single reusable instance** — created in `RUMFeature.init`, `start()` resets all state (buffers, timer) cleanly per session.
- **Session context injected at `start()`** — `RUMSessionScope` calls `collector.start(sessionID:applicationID:)` so the collector always has fresh context for the new session.
- **Collection scope: session** — start on session start, stop on session end, flush remaining buffer.
- **Opt-in via RUM config flag** — `RUM.Configuration.enableTimeseries: Bool = false`.
- **Upload: existing RUM Writer** — no new storage scope or upload worker.

---

## Schema C DataPoint Encoding

**Before (Schema B):**
```json
{ "timestamp": 1714000000000000000, "data_point_value": 38052032.0 }
```

**After (Schema C):**
```json
{
  "timestamp": 1776690660041000000,
  "data_point": {
    "memory_max": 115456128.5,
    "memory_percent": 76.8
  }
}
```

The value is wrapped in a nested `data_point` object with named metric fields. This uses **static `CodingKeys`** — fully compatible with code generation.

**Memory data point fields:**
- `memory_max` — raw bytes from `VitalMemoryReader.readVitalData()` (`phys_footprint`)
- `memory_percent` — `memory_max / ProcessInfo.processInfo.physicalMemory * 100`

**CPU data point fields (to confirm exact names with backend):**
- `cpu_usage` — CPU percentage from `VitalCPUReader.readVitalData()`

**Generated struct shape (from rum-events-format):**
```swift
// RUMDataModels.swift (generated)
public struct RUMTimeseriesMemoryEvent: RUMDataModel {
    // ... envelope fields ...
    public struct DataPoint: Codable {
        public let timestamp: Int64
        public let dataPoint: MemoryDataPoint
        public struct MemoryDataPoint: Codable {
            public let memoryMax: Double
            public let memoryPercent: Double
            // CodingKeys: memory_max, memory_percent
        }
    }
}
```

---

## Architecture

```
RUM.Configuration.enableTimeseries = true
        │
        ▼
RUMFeature.init
  → creates TimeseriesSessionCollector(memoryReader:, cpuReader:, writer:, config:)
  → injects into RUMScopeDependencies
        │
        ▼
RUMSessionScope.init
  → dependencies.timeseriesCollector?.start()
        │
        ▼
Timer @ 1s:
  → memoryReader.readVitalData() → Sample → memoryBuffer.append
  → cpuReader.readVitalData()    → Sample → cpuBuffer.append
  → if buffer.count >= batchSize: flush(metric, buffer) → Writer.write(event)
        │
RUMSessionScope ends
  → dependencies.timeseriesCollector?.stop()  (flushes remaining)
```

---

## How the Event Model Gets Into the SDK

RUM event types in this SDK are **not hand-written**. The flow is:

1. Schema defined as JSON Schema in the [`rum-events-format`](https://github.com/DataDog/rum-events-format) repo
2. `make rum-models-generate` runs a codegen tool → appends the generated Swift struct to `DatadogInternal/Sources/Models/RUM/RUMDataModels.swift`
3. The generated struct conforms to `RUMDataModel` (which is `Codable`) and uses explicit `CodingKeys`
4. `TimeseriesSessionCollector` uses this generated type when writing events

Since we work off a feature branch on `rum-events-format` (`bplasovska/timeseries`) without needing a merged PR, the generated type is available on the iOS branch from the start of Phase 2.

---

## Tasks

### Phase 0 — rum-events-format schema

0. **Create branch `bplasovska/timeseries` on `rum-events-format`** and define two JSON Schemas there (no PR needed)
   - **`RUMTimeseriesMemoryEvent`**: envelope + `timeseries.data: [{ timestamp, data_point: { memory_max: Double, memory_percent: Double } }]`
   - **`RUMTimeseriesCPUEvent`**: envelope + `timeseries.data: [{ timestamp, data_point: { cpu_usage: Double } }]` (confirm exact CPU field names with backend)
   - Both share the same envelope shape: `{ _dd, application, session, source, type, service, version, date, timeseries: { id, name, start, end, data } }`
   - Run `make rum-models-generate GIT_REF=bplasovska/timeseries` on the iOS branch → generated structs appear in `RUMDataModels.swift`

### Phase 1 — Schema C in standalone package

1. **Update `TimeseriesEvent.DataPoint`** in `DatadogTimeseries/Sources/DatadogTimeseries/Models/TimeseriesEvent.swift`
   - Replace `dataPointValue: Double` (CodingKey `data_point_value`) with Schema C nested shape
   - `DataPoint` becomes `{ timestamp: Int64, dataPoint: [String: Double] }` — encodes as `{ "timestamp": ..., "data_point": { "memory_max": ..., "memory_percent": ... } }`
   - `dataPoint` is a `[String: Double]` dictionary (flexible for runner/demo use; the SDK uses generated typed structs)

2. **Update `TimeseriesEventBuilder`** to populate `dataPoint` dictionary with the correct metric keys per `TimeseriesName`

3. **Update fixture files** (`expected_memory_batch1.json`, `expected_cpu_batch1.json`) to Schema C format

4. **Update `DatadogTimeseriesRunner`** — output still valid after schema change

5. **Run standalone tests** — all must pass after schema migration

### Phase 2 — Timeseries infrastructure in DatadogRUM

6. **Create `DatadogRUM/Sources/Timeseries/TimeseriesSessionCollector.swift`**
   - `TimeseriesSessionCollector` — manages two metric streams (memory + CPU)
   - `init(memoryReader:cpuReader:batchSize:featureScope:)`
   - `start(sessionID:applicationID:)` — resets buffers, starts dedicated 1s `DispatchSourceTimer` on a background serial queue
   - `stop()` — cancels timer, flushes remaining buffers for both metrics
   - Timer handler: read both vitals; for memory compute `memory_percent = bytes / ProcessInfo.processInfo.physicalMemory * 100`; append to respective buffer; flush if buffer.count >= batchSize
   - `flush(metric:buffer:)` — builds `RUMTimeseriesMemoryEvent` or `RUMTimeseriesCPUEvent` from `RUMDataModels.swift`, writes via `featureScope.eventWriteContext { _, writer in writer.write(value: event) }`
   - Thread-safe: all buffer access on dedicated serial queue

### Phase 3 — Wire into RUM

7. **Update `RUM.Configuration`** (`DatadogRUM/Sources/RUMConfiguration.swift`)
    - Add `public var enableTimeseries: Bool = false`

8. **Update `RUMScopeDependencies`** (`DatadogRUM/Sources/RUMMonitor/Scopes/RUMScopeDependencies.swift`)
    - Add `timeseriesCollector: TimeseriesSessionCollector?`

9. **Update `RUMFeature.init`** (`DatadogRUM/Sources/Feature/RUMFeature.swift`)
    - If `configuration.enableTimeseries && vitalsReaders != nil`:
      - Create `TimeseriesSessionCollector` with memory + CPU readers and the feature scope
      - Inject into `RUMScopeDependencies`

10. **Update `RUMSessionScope`** (`DatadogRUM/Sources/RUMMonitor/Scopes/RUMSessionScope.swift`)
    - In `init`: call `dependencies.timeseriesCollector?.start(sessionID: sessionUUID.toRUMDataFormat, applicationID: dependencies.rumApplicationID)`
    - On session end (at the existing expiry/stop call site, following Marie's prototype pattern): call `dependencies.timeseriesCollector?.stop()`

### Phase 4 — Tests

11. **`DatadogTimeseriesTests`** (standalone package):
    - Update encoding tests to assert Schema C field names
    - Verify fixture JSON matches Schema C format

12. **`DatadogRUMTests`** (SDK):
    - `TimeseriesSessionCollectorTests` — batching, flush on stop, thread safety, correct generated type used
    - `RUMSessionScopeTests` — collector started/stopped with session (mock collector)

---

## Verification Strategy

After each phase:
1. **Unit tests** — `swift test --package-path DatadogTimeseries` (standalone) and `make test-ios SCHEME="DatadogRUM iOS"` (SDK)
2. **Runner script** — after Schema C changes, run `DatadogTimeseriesRunner` against the fixture CSV and assert the output JSON matches the Schema C `data_point` nested shape
3. **Linter** — `./tools/lint/run-linter.sh` after each new/modified file

---

## What is NOT in scope

- Deadband / Window filters (Plan 3 deferred)
- Android integration (parallel track)
- Merging the `bplasovska/timeseries` branch into rum-events-format main (no PR needed for this phase)
- Per-session size limiting / data cap enforcement (experiments running in parallel)
- Custom metrics beyond memory_usage and cpu_usage

---

## Files to create

| File | Purpose |
|------|---------|
| `DatadogRUM/Sources/Timeseries/TimeseriesSessionCollector.swift` | Session-level collector (memory + CPU) |
| `DatadogRUM/Tests/DatadogRUMTests/Timeseries/TimeseriesSessionCollectorTests.swift` | Collector tests |

## Files to modify

| File | Change |
|------|--------|
| `DatadogTimeseries/Sources/DatadogTimeseries/Models/TimeseriesEvent.swift` | Schema C DataPoint |
| `DatadogInternal/Sources/Models/RUM/RUMDataModels.swift` | Generated — run `make rum-models-generate GIT_REF=bplasovska/timeseries` |
| `DatadogRUM/Sources/RUMConfiguration.swift` | Add `enableTimeseries` flag |
| `DatadogRUM/Sources/RUMMonitor/Scopes/RUMScopeDependencies.swift` | Add `timeseriesCollector` |
| `DatadogRUM/Sources/Feature/RUMFeature.swift` | Create + inject collector |
| `DatadogRUM/Sources/RUMMonitor/Scopes/RUMSessionScope.swift` | Start/stop collector |
| Fixture JSON files | Schema C format |

---

## Open Questions

- Does `TimeseriesSessionCollector` need access to `DatadogContext` for `source`, `service`, `version`? (Yes — pass at `start(with:)` or `init`)
- Should `enableTimeseries` only activate if `vitalsUpdateFrequency != nil`? (Yes — guard at collector creation)
- ~~What is the `type` field value for timeseries events in the RUM schema?~~ → **`"timeseries"`** (confirmed from `TimeseriesEventBuilder.build()` in both the standalone package and Marie's prototype)
