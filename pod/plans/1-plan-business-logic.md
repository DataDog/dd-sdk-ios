# PLAN.md — DatadogTimeseries Standalone Package

**Date:** 2026-04-13
**Epic:** RUM-13949
**Pod:** AI-first Performance Timeseries
**Author:** Barbora Plasovska

---

## Idea Summary

Standalone Swift package (`DatadogTimeseries`) with zero SDK dependencies that implements the pure timeseries transform logic: takes timestamped performance samples (memory, CPU) and produces complete RUM timeseries JSON events. Runs with `swift build` / `swift test` only. Includes a verification pipeline (CSV fake data in, expected JSON out, exact match comparison). Lives on a feature branch in dd-sdk-ios.

### Why standalone?

This package is designed for fast agent-driven iteration:
- `swift build` compiles in seconds — no Xcode workspace, no simulators, no Carthage, no CocoaPods
- `swift test` runs all tests headlessly — the agent can loop (edit → test → fix) autonomously in YOLO mode
- Zero SDK dependencies means zero setup — clone, `cd DatadogTimeseries/`, `swift test`, done

### Two-plan approach

This is **Plan 1 of 2**:
- **Plan 1 (this plan):** Build and verify the standalone package — pure logic, CSV in, JSON out, verification pipeline
- **Plan 2 (separate IPCIVR session, Week 2+):** Integrate into DatadogRUM — replace CSVDataProvider with real VitalMemoryReader/VitalCPUReader, wire into RUM session lifecycle, connect to the upload pipeline

Plan 2 starts once Plan 1 is solid and verified. The integration is glue code on top of a battle-tested transform library.

---

## Decisions Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Consumers | Both RUM Investigation Agent + Mobile Vitals | Both are first-class from day 1 |
| Event scope | Full RUM envelope | Package produces complete JSON events (with application, session, _dd) |
| Timer/scheduling | Platform glue (not in package) | Package is pure stateless transform |
| Delta compression | Deferred to Week 2+ | Simpler first iteration |
| RUM context injection | Config struct | Simple TimeseriesConfig passed at init |
| CSV format | timestamp,metric,value | Three-column, one CSV for all metrics |
| JSON encoding | Codable + .sortedKeys | Type-safe AND deterministic output for exact match |
| Batching | Package enforces | Batcher accumulates samples, flushes at batch size |
| DataProvider | Pull-based sync | `func read() -> Sample?` — matches VitalMemoryReader pattern |
| Fixture generation | Backend-driven | Hand-write from staging schema, validate with William |
| Timestamps | Event date in ms, start/end/data_point in ns | Matches staging schema |
| Error handling | Skip failed samples | Log warning, leave gap, continue |
| UUID comparison | Mask before diff | Replace UUIDs with placeholder for verification |
| Output format | Individual JSON events | Batching into NDJSON is platform glue |
| Location | Feature branch in dd-sdk-ios | Directory at repo root: `DatadogTimeseries/` |

---

## Architecture

```
DatadogTimeseries/
├── Package.swift                         # Zero external dependencies
├── Sources/
│   └── DatadogTimeseries/
│       ├── Models/
│       │   ├── TimeseriesEvent.swift     # Codable RUM timeseries event (full envelope)
│       │   ├── TimeseriesName.swift      # Enum: memory_usage, cpu_usage
│       │   └── Sample.swift              # (timestamp: Int64, value: Double) value type
│       ├── DataProvider/
│       │   ├── DataProvider.swift         # Protocol: func read() -> Sample?
│       │   └── CSVDataProvider.swift      # Reads CSV fixtures for testing
│       ├── Core/
│       │   ├── TimeseriesConfig.swift     # RUM context: app id, session id, source, etc.
│       │   ├── TimeseriesBatcher.swift    # Accumulates samples, flushes at batch size
│       │   └── TimeseriesEventBuilder.swift  # Samples → RUM JSON event
│       ├── Encoding/
│       │   └── TimeseriesEncoder.swift    # JSONEncoder wrapper with sorted keys
│       └── TimeseriesPipeline.swift       # Convenience: wires provider → batcher → builder → encoder
├── Tests/
│   └── DatadogTimeseriesTests/
│       ├── Fixtures/
│       │   ├── input_memory_cpu.csv       # Fake input: timestamp,metric,value
│       │   ├── expected_memory_batch1.json # Expected output for memory batch 1
│       │   ├── expected_memory_batch2.json # Expected output for memory batch 2
│       │   ├── expected_cpu_batch1.json    # Expected output for CPU batch 1
│       │   └── expected_cpu_batch2.json    # Expected output for CPU batch 2
│       ├── CSVDataProviderTests.swift
│       ├── TimeseriesBatcherTests.swift
│       ├── TimeseriesEventBuilderTests.swift
│       ├── TimeseriesEncoderTests.swift
│       └── EndToEndVerificationTests.swift  # CSV in → JSON out → exact match
└── Scripts/                               # Reserved for future tooling
```

---

## Data Flow

```
CSV file                    TimeseriesConfig
    │                            │
    ▼                            │
CSVDataProvider                  │
    │                            │
    ▼                            │
  Sample(timestamp, value)       │
    │                            │
    ▼                            │
TimeseriesBatcher                │
    │  (accumulates N samples)   │
    │  (flushes when full)       │
    ▼                            ▼
TimeseriesEventBuilder ◄─────────┘
    │
    ▼
TimeseriesEvent (Codable struct)
    │
    ▼
TimeseriesEncoder (.sortedKeys)
    │
    ▼
JSON string (deterministic)
    │
    ▼
Compare vs expected fixture (exact match, UUIDs masked)
```

---

## Task Breakdown

### Task 1: Package scaffolding
Create the Swift package structure with `Package.swift`, directory layout, empty source files.
- No external dependencies
- Targets: `DatadogTimeseries` (library) + `DatadogTimeseriesTests` (test)
- Swift 5.9+ (match dd-sdk-ios)

### Task 2: Models
Define the core data types:

**Sample.swift:**
```swift
struct Sample {
    let timestamp: Int64  // nanoseconds
    let value: Double
}
```

**TimeseriesName.swift:**
```swift
enum TimeseriesName: String, Codable {
    case memoryUsage = "memory_usage"
    case cpuUsage = "cpu_usage"
}
```

**TimeseriesEvent.swift** (Codable, full RUM envelope):
```swift
struct TimeseriesEvent: Codable {
    let dd: DD                    // { format_version: 2 }
    let application: Application  // { id: String }
    let date: Int64               // milliseconds
    let session: Session          // { id: String, type: "user" }
    let source: String            // "ios"
    let type: String              // "timeseries"
    let service: String?
    let version: String?
    let timeseries: Timeseries

    struct DD: Codable {
        let formatVersion: Int  // 2
    }
    struct Application: Codable {
        let id: String
    }
    struct Session: Codable {
        let id: String
        let type: String  // "user"
    }
    struct Timeseries: Codable {
        let id: String           // UUID
        let name: TimeseriesName
        let start: Int64         // nanoseconds
        let end: Int64           // nanoseconds
        let data: [DataPoint]
    }
    struct DataPoint: Codable {
        let timestamp: Int64         // nanoseconds
        let dataPointValue: Double
    }
}
```

Use explicit `CodingKeys` on every struct to map to snake_case (`format_version`, `data_point_value`, `_dd`). No `.convertToSnakeCase` encoder strategy — CodingKeys gives full control over edge cases like `_dd` and avoids double-conversion bugs.

### Task 3: TimeseriesConfig
```swift
struct TimeseriesConfig {
    let applicationId: String
    let sessionId: String
    let sessionType: String       // "user"
    let source: String            // "ios"
    let service: String?
    let version: String?
}
```

### Task 4: DataProvider protocol + CSVDataProvider

**DataProvider.swift:**
```swift
protocol DataProvider {
    func read() -> Sample?
}
```

**CSVDataProvider.swift:**
- Reads a CSV file with format: `timestamp,metric_name,value`
- Filters by a given `TimeseriesName`
- Returns samples one by one via `read()` (pull-based)
- Returns `nil` when exhausted

### Task 5: TimeseriesBatcher
- Initialized with `batchSize: Int` (default 30) — metric-agnostic, it just batches samples
- `add(_ sample: Sample)` — appends to internal buffer
- `shouldFlush() -> Bool` — true when buffer.count >= batchSize
- `flush() -> [Sample]` — returns accumulated samples, clears buffer
- `flushRemaining() -> [Sample]?` — returns whatever is left (for session end), nil if empty

### Task 6: TimeseriesEventBuilder
- Initialized with `TimeseriesConfig`
- `build(samples: [Sample], name: TimeseriesName, eventId: String) -> TimeseriesEvent`
- Computes `start` = first sample timestamp, `end` = last sample timestamp
- Computes `date` = `start` converted from ns to ms (integer division by 1_000_000)
- Maps samples to `DataPoint` array

### Task 7: TimeseriesEncoder
- Wraps `JSONEncoder` with:
  - `.sortedKeys` output formatting
  - No `.convertToSnakeCase` — all snake_case mapping handled by explicit CodingKeys on the model structs
- `func encode(_ event: TimeseriesEvent) -> Data`
- Returns deterministic JSON bytes

### Task 8: CSV test fixtures
Create `input_memory_cpu.csv` with realistic fake data:
- ~20 rows (10 `memory_usage` + 10 `cpu_usage`, simulating 10 seconds at 1Hz)
- Memory values in ~30-40 MB range (bytes), CPU values in 0-100 range (percent)
- Timestamps in nanoseconds, 1-second intervals starting from a fixed epoch
- Tests use `batchSize=5` so this produces 2 batches per metric (4 expected JSON files)
- Production default of 30 is a tuning concern for Plan 2, not a verification concern here

### Task 9: Expected JSON fixtures (backend-driven)
The expected JSON fixtures should represent what the backend actually accepts. Two-step approach:
1. **Hand-write initial fixtures** based on the staging schema contract (the JSON format already documented in the kickoff context + what William's backend validates against)
2. **Validate with William** — share the fixture files with William/backend team to confirm they match the intake contract. If the backend rejects the format, the fixtures are wrong regardless of what our code produces.

This avoids the "testing our code with our code" problem — the expected output is defined by the backend contract, not by our own generator.

Files:
- `Tests/DatadogTimeseriesTests/Fixtures/expected_memory_batch1.json`
- `Tests/DatadogTimeseriesTests/Fixtures/expected_memory_batch2.json`
- `Tests/DatadogTimeseriesTests/Fixtures/expected_cpu_batch1.json`
- `Tests/DatadogTimeseriesTests/Fixtures/expected_cpu_batch2.json`
- All with masked UUIDs (`00000000-0000-0000-0000-000000000000`) and sorted keys

### Task 10: Unit tests
- **CSVDataProviderTests**: reads CSV, filters by metric, returns correct samples, returns nil at end
- **TimeseriesBatcherTests**: accumulates correctly, flushes at batch size, flushRemaining works, empty flush returns nil
- **TimeseriesEventBuilderTests**: correct envelope fields, correct start/end, correct data points, correct timestamps
- **TimeseriesEncoderTests**: sorted keys, snake_case, valid JSON

### Task 11: End-to-end verification test
`EndToEndVerificationTests.swift`:
1. Read `input_memory_cpu.csv` via `CSVDataProvider`
2. Feed samples through `TimeseriesBatcher` + `TimeseriesEventBuilder` + `TimeseriesEncoder`
3. Mask UUIDs in actual output (regex replace UUID pattern with `"00000000-0000-0000-0000-000000000000"`)
4. Load expected JSON fixture (already has masked UUIDs)
5. Compare byte-for-byte
6. Pass/fail

### Task 12: TimeseriesPipeline (orchestrator)
- Convenience type that wires the full flow: `DataProvider` → `TimeseriesBatcher` → `TimeseriesEventBuilder` → `TimeseriesEncoder`
- `init(provider: DataProvider, config: TimeseriesConfig, metricName: TimeseriesName, batchSize: Int)`
- `func processAll() -> [Data]` — reads all samples from provider, batches, builds events, encodes, returns JSON data array
- This is what the E2E test calls — keeps wiring logic out of the test itself
- In Plan 2 (platform integration), the real orchestrator is the session scope + timer, not this pipeline

### Task 13: Skip-sample error handling
- `DataProvider.read()` returns `Sample?` — nil means skip
- `TimeseriesBatcher.add()` only accepts non-nil samples
- Test: CSV with a gap (missing row) → output event has fewer data points, timestamps reflect the gap

---

## Verification Strategy

The agent must run these checks **in order** after every change:

### 1. Build check
```bash
cd DatadogTimeseries && swift build
```
Must compile with zero errors and zero warnings. Fastest feedback — catches type errors, missing imports, syntax issues.

### 2. Unit tests
```bash
cd DatadogTimeseries && swift test
```
Runs all tests in `DatadogTimeseriesTests`. Each component has dedicated tests (Tasks 10). Pass/fail is unambiguous.

### 3. End-to-end exact match
Part of `swift test` (Task 11) — the `EndToEndVerificationTests`:
- CSV in → pipeline → JSON out → mask UUIDs → compare byte-for-byte against expected fixtures
- UUID masking regex: `[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}` → `00000000-0000-0000-0000-000000000000`
- Fixtures are hand-written from backend contract (validated with William)

### 4. JSON schema validation
A test that validates output JSON structure against expected RUM timeseries schema:
- Required fields present: `_dd`, `application`, `date`, `session`, `source`, `type`, `timeseries`
- Correct types: `date` is Int64, `timeseries.data` is array, `data_point_value` is Double
- Correct constants: `type` == `"timeseries"`, `_dd.format_version` == 2, `session.type` == `"user"`
- This catches structural errors even before fixtures are finalized

### Agent loop
After every code change, the agent runs:
```bash
cd DatadogTimeseries && swift build && swift test
```
All green = proceed. Any red = fix before moving on.

---

## Week 1 Milestone (Friday Apr 18 Demo)

- [ ] Package compiles with `swift build`
- [ ] All unit tests pass with `swift test`
- [ ] End-to-end verification passes (CSV in → JSON out → exact match)
- [ ] Can show: "same CSV input, same expected JSON — ready for Kotlin/Go to verify against"

---

## Future (Week 2+)

- Delta compression (DeltaEncoder)
- Integration into DatadogRUM (replace CSVDataProvider with VitalMemoryReader/VitalCPUReader)
- Wire TimeseriesEventBuilder output into RUM Writer pipeline
- NDJSON batch format for upload
- Kotlin rewrite + verification against same fixtures
- Configurable batch size tuning based on backend feedback
