# Plan 3 — Sampling Filters for DatadogTimeseries Standalone Package

**Date:** 2026-04-15
**Epic:** RUM-13949
**Phase:** Post-MVP research — compare sampling strategies before Plan 2 integration

---

## Goal

Add pluggable `SampleFilter` protocol to the standalone `DatadogTimeseries` Swift package with 2 concrete implementations (PassThrough, Deadband, WindowAggregate). Wire it into `TimeseriesPipeline`, generate a realistic 60-sample fixture, and provide a runner script that compares all strategies side by side.

This is a **research tool**, not a production feature. The filters and fixture generated here inform which strategy carries into Plan 2 (SDK integration). The JSON output from each filter feeds into the real backend pipeline.

---

## Architecture

The filter slots between `DataProvider` and `TimeseriesBatcher` inside `TimeseriesPipeline.processAll()`:

```
DataProvider → [SampleFilter] → TimeseriesBatcher → EventBuilder → Encoder
```

Protocol shape (class-only for clean mutable state):

```swift
protocol SampleFilter: AnyObject {
    func process(_ sample: Sample) -> [Sample]  // 0 = suppress, 1+ = forward
    func flush() -> [Sample]                     // emit buffered state at end of stream
}
```

Default filter is `PassThroughFilter()` — existing tests are unaffected.

---

## Decisions Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| SampleFilter type | Class-only protocol (AnyObject) | Filters are stateful. Reference semantics avoid inout/wrapper complexity. |
| TransitionFilter | **Dropped from this plan** | Not meaningful for continuous metrics (memory, CPU). Build later for thermal/battery state. |
| Fixture size | 60 samples (1 min at 1 Hz) | Small enough to inspect, large enough to show meaningful filter differences. |
| Fixture shape | Realistic: slow memory growth + CPU spikes | Matches real-world patterns. 3 allocation jumps, 3 CPU bursts. |
| Fixture generator | Python/shell script | Simpler than standalone Swift script (can't import the package). |
| Filter scope | Any filter on any metric | One --filter arg applies to both memory and CPU. Flexible for research. |
| Deadband threshold | Configurable via --threshold | Lets you experiment without code changes. |
| Deadband heartbeat | Configurable via --heartbeat | Important so backend can distinguish "stable value" from "collection stopped". |
| Window duration | Configurable via --window (seconds) | Try 5s vs 10s vs 30s without code changes. |
| Aggregate function | Configurable via --aggregate max\|avg\|min\|last | All 4 are useful; max for spike detection, avg for baseline. |
| Table aggregate | Uses --aggregate arg for window row | Comparison table reflects the active configuration. |
| JSON output | All 3 filters written every run | Script runs all 3 internally; no reason to discard any result. |
| Output cleanup | Clear output/ at start of each run | Prevents accidentally curling a stale file from a previous run. |
| Pipeline default | PassThroughFilter() | Existing E2E fixture tests are unchanged. New filter tests are additive. |
| Script location | DatadogTimeseries/scripts/ | Self-contained next to the code. Goes away naturally with the standalone package. |

---

## Tasks

### Task 1 — `SampleFilter` protocol
**File:** `Sources/DatadogTimeseries/Filters/SampleFilter.swift`

Protocol definition. Class-only (`AnyObject`). Two methods: `process` and `flush`. Include inline doc explaining when each is called.

---

### Task 2 — `PassThroughFilter`
**File:** `Sources/DatadogTimeseries/Filters/PassThroughFilter.swift`

Returns `[sample]` always, `flush()` returns `[]`. Makes the current implicit pipeline behaviour explicit. Zero logic.

---

### Task 3 — `DeadbandFilter`
**File:** `Sources/DatadogTimeseries/Filters/DeadbandFilter.swift`

```swift
final class DeadbandFilter: SampleFilter {
    init(threshold: Double, heartbeatInterval: Int64? = nil)
}
```

State: `lastEmittedValue: Double?`, `lastEmittedTimestamp: Int64?`

Logic:
- Always emit the first sample
- Emit if `abs(current.value - lastEmitted.value) >= threshold`
- Emit if `heartbeatInterval != nil && (current.timestamp - lastEmitted.timestamp) >= heartbeatInterval`
- `flush()` returns `[]` (no internal buffer)

---

### Task 4 — `WindowAggregateFilter`
**File:** `Sources/DatadogTimeseries/Filters/WindowAggregateFilter.swift`

```swift
enum AggregateFunction { case avg, min, max, last }

final class WindowAggregateFilter: SampleFilter {
    init(windowDuration: Int64, function: AggregateFunction = .max)
}
```

State: `windowStart: Int64?`, `buffer: [Sample]`

Logic:
- Accumulate samples in buffer
- When `sample.timestamp - windowStart >= windowDuration`: flush window, emit one aggregate sample, start new window
- `flush()`: emit aggregate of remaining buffer (partial window at end of stream)
- Emitted sample timestamp = `windowStart`
- Aggregate: avg = mean, min = minimum, max = maximum, last = last sample's value

---

### Task 5 — Update `TimeseriesPipeline`
**File:** `Sources/DatadogTimeseries/TimeseriesPipeline.swift`

```swift
init(
    provider: DataProvider,
    config: TimeseriesConfig,
    metricName: TimeseriesName,
    batchSize: Int = 30,
    filter: SampleFilter = PassThroughFilter()
)
```

Update `processAll()`:
```
while let raw = provider.read() {
    let filtered = filter.process(raw)
    for sample in filtered { batcher.add + maybe flush }
}
// After provider exhausted:
for sample in filter.flush() { batcher.add + maybe flush }
// Then existing batcher.flushRemaining() tail
```

---

### Task 6 — Realistic 60-sample fixture generator
**File:** `DatadogTimeseries/scripts/generate-fixture.py`

Generates `Tests/DatadogTimeseriesTests/Fixtures/input_realistic_60s.csv`.

Memory shape (60 rows):
- Base: 31_000_000 bytes (~31MB)
- Slow drift: +1_000–3_000 bytes/s (noise)
- 3 allocation jumps: +1_500_000 bytes at ~t=12s, +2_000_000 at ~t=30s, +1_000_000 at ~t=50s
- One deallocation: -500_000 at ~t=40s

CPU shape (60 rows):
- Baseline: 5–15% (random noise in range)
- 3 bursts: 50–80% for 3–5 seconds at ~t=15s, ~t=35s, ~t=55s

CSV format: same as existing fixture (`timestamp,metric,value`), timestamps at 1s intervals starting from `1700000001000000000`.

---

### Task 7 — Unit tests per filter
**Files:**
- `Tests/DatadogTimeseriesTests/Filters/PassThroughFilterTests.swift`
- `Tests/DatadogTimeseriesTests/Filters/DeadbandFilterTests.swift`
- `Tests/DatadogTimeseriesTests/Filters/WindowAggregateFilterTests.swift`

**PassThroughFilterTests:** passes all samples, flush returns empty.

**DeadbandFilterTests:**
- Always emits first sample
- Suppresses sample below threshold
- Emits at exact threshold
- Emits on negative delta
- References last *emitted* value, not last *seen*
- Heartbeat fires after silence interval
- No heartbeat without interval configured
- Flush returns nothing

**WindowAggregateFilterTests:**
- Does not emit until window closes
- Emits when window closes (timestamp = window start)
- flush() emits partial window
- flush() on empty buffer returns nothing
- Multiple windows each emit once
- Each aggregate function (avg, min, max, last) produces correct value
- Realistic CPU scenario: 10 samples, 5s window, max → 2 aggregate events with correct max values

---

### Task 8 — `FilterComparisonTests`
**File:** `Tests/DatadogTimeseriesTests/Filters/FilterComparisonTests.swift`

Uses `input_realistic_60s.csv` (60 samples).

Tests:
- PassThrough on memory/CPU: 60 data points each
- Deadband (threshold=1_000_000) on memory: fewer than 60 data points, includes first sample
- Deadband (threshold=1_000_000) on CPU: tests that spikes cross threshold
- Window (5s, max) on CPU: exactly 12 data points (60s / 5s)
- Window (5s, max) on CPU: max values correctly capture burst peaks
- All filters produce valid JSON (type="timeseries", required fields present)
- Pipeline default (no filter arg) = PassThrough behaviour (regression guard)

---

### Task 9 — Runner script
**File:** `DatadogTimeseries/scripts/run-pipeline.sh`

```bash
./scripts/run-pipeline.sh [--filter passthrough|deadband|window]
                          [--threshold <bytes>]     # deadband threshold (default: 1000000)
                          [--heartbeat <seconds>]   # deadband heartbeat (default: 30)
                          [--window <seconds>]      # window duration (default: 5)
                          [--aggregate max|avg|min|last]  # window function (default: max)
```

**Behaviour:**

1. Clear `output/` directory
2. Run `swift test` — exit on failure
3. Run all 3 filters against `input_realistic_60s.csv` for both memory and CPU using the provided params (deadband uses --threshold/--heartbeat, window uses --window/--aggregate)
4. Print comparison table:

```
┌─────────────────┬───────────────────────────────┬───────────────────────────────┐
│ Filter          │ Memory                        │ CPU                           │
│                 │ events │ data pts │ reduction  │ events │ data pts │ reduction  │
├─────────────────┼────────┼──────────┼────────────┼────────┼──────────┼────────────┤
│ passthrough     │      6 │       60 │       --   │      6 │       60 │       --   │
│ deadband        │      2 │       18 │      70%   │      4 │       32 │      47%   │
│ window (max,5s) │      2 │       12 │      80%   │      2 │       12 │      80%   │
└─────────────────┴────────┴──────────┴────────────┴────────┴──────────┴────────────┘
```

5. Write all 3 filters' output to `output/`:
   - `output/passthrough_memory.ndjson`, `output/passthrough_cpu.ndjson`
   - `output/deadband_memory.ndjson`, `output/deadband_cpu.ndjson`
   - `output/window_memory.ndjson`, `output/window_cpu.ndjson`
6. Pretty-print first event from the `--filter` selection (default: all 3)

**Script is self-contained** — uses `swift` CLI to run a small Swift driver program that imports `DatadogTimeseries` and runs the pipeline, piping output back to the shell script for display.

---

## Verification Strategy

See Phase 4 output (to be determined).

---

## What this is NOT

- Not a production feature — the standalone package gets removed after Plan 2
- Not a backend integration — the JSON files are ready to curl, but curling is manual
- `TransitionFilter` is intentionally out of scope — build when enum-like metrics are added
