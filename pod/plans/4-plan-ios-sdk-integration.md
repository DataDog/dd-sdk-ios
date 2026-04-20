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

- **Schema C** — DataPoint encodes as `{ "timestamp": ..., "memory_usage": 42.0 }` or `{ "timestamp": ..., "cpu_usage": 5.2 }`. One named field per data point, named after the metric.
- **No cross-package import** — `DatadogRUM` does not import `DatadogTimeseries`. Avoids SPM dependency between a standalone experimental package and the production SDK. Standalone package stays for demo/runner use only.
- **PassThrough filter only** — no sampling for this integration. Deadband/Window deferred.
- **Batch size: 30** — matches the standalone package default, ~30 seconds of data per event.
- **Sampling interval: 1s** — reuse the existing `VitalInfoSampler` timer or a dedicated 1s timer.
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
{ "timestamp": 1714000000000000000, "memory_usage": 38052032.0 }
{ "timestamp": 1714000000000000000, "cpu_usage": 5.2 }
```

Implementation: `DataPoint` uses a dynamic `CodingKey` so the value field name comes from the metric:

```swift
struct TimeseriesDataPoint: Encodable {
    let timestamp: Int64
    let metricName: String  // "memory_usage" or "cpu_usage"
    let value: Double

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(timestamp, forKey: .init("timestamp"))
        try container.encode(value, forKey: .init(metricName))
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

0. **Create branch `bplasovska/timeseries` on `rum-events-format`** and define the `TimeseriesEvent` JSON Schema there (no PR needed)
   - Schema C shape: `{ "_dd", "application", "session", "source", "type", "service", "version", "date", "timeseries": { "id", "name", "start", "end", "data": [{ "timestamp", "<metric_name>": value }] } }`
   - Each metric gets its own data point schema (static keys): `memory_usage` event uses a `DataPoint` with `memory_usage: Double`; `cpu_usage` event uses a `DataPoint` with `cpu_usage: Double`
   - Run `make rum-models-generate GIT_REF=bplasovska/timeseries` on the iOS branch → generated structs appear in `RUMDataModels.swift`
   - **No placeholder needed:** since we can generate from the branch immediately, skip the `_TimeseriesEventPlaceholder.swift` approach

### Phase 1 — Schema C in standalone package

1. **Update `TimeseriesEvent.DataPoint`** in `DatadogTimeseries/Sources/DatadogTimeseries/Models/TimeseriesEvent.swift`
   - Replace `dataPointValue: Double` (CodingKey `data_point_value`) with dynamic encoding
   - Add `DynamicCodingKey` helper
   - `DataPoint` becomes `{ timestamp, metricName, value }` — encodes value under `metricName`

2. **Update `TimeseriesEventBuilder`** to pass the metric name when creating DataPoints

3. **Update fixture files** (`expected_memory_batch1.json`, `expected_cpu_batch1.json`) to Schema C format

4. **Update `DatadogTimeseriesRunner`** — output still valid after schema change

5. **Run standalone tests** — all must pass after schema migration

### Phase 2 — Timeseries infrastructure in DatadogRUM

6. **Create `DatadogRUM/Sources/Timeseries/TimeseriesSessionCollector.swift`**
   - `TimeseriesSessionCollector` — manages two metric streams (memory + CPU)
   - `init(memoryReader:cpuReader:batchSize:writer:context:)`
   - `start()` — starts 1s Timer on a background DispatchQueue
   - `stop()` — invalidates timer, flushes remaining buffers
   - Timer handler: read both vitals, append to respective buffer, flush if at batch size
   - `flush(metric:buffer:)` — builds event using the generated type from `RUMDataModels.swift`, writes via `FeatureScope.eventWriteContext { _, writer in writer.write(value: event) }`
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
    - In `init`: call `dependencies.timeseriesCollector?.start(with: context)`
    - On session end: call `dependencies.timeseriesCollector?.stop()`

### Phase 4 — Tests

11. **`DatadogTimeseriesTests`** (standalone package):
    - Update encoding tests to assert Schema C field names
    - Verify fixture JSON matches Schema C format

12. **`DatadogRUMTests`** (SDK):
    - `TimeseriesSessionCollectorTests` — batching, flush on stop, thread safety, correct generated type used
    - `RUMSessionScopeTests` — collector started/stopped with session (mock collector)

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
