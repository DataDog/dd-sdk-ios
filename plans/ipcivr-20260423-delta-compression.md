# IPCIVR Plan — Delta Compression for Timeseries
**Date:** 2026-04-23

## Idea Summary
- Add `enableDeltaCompression: Bool = false` to `TimeseriesSessionCollector` on both iOS and Android
- When `true`, replace the normal `data: [{timestamp, data_point}]` array with a columnar delta object `{precision:4, ts:[...], field:[...]}` for both memory and CPU flushes
- Precision hardcoded to 4 — floats multiplied by `10^4`, stored as integer deltas
- Single-sample batches are dropped (no degenerate delta objects sent)
- Each flush logs `[Timeseries] delta flush: signal=X normal=YB delta=ZB ratio=Wx` for staging comparison
- Flag defaults `false` — demo path completely unaffected; staged override set locally only (not committed)

## Decisions
- Flag location: `TimeseriesSessionCollector` constructor (not RUM config)
- Scope: both memory and CPU signals
- Precision: hardcoded `4`
- iOS serialization: encode normal event → patch `[String:Any]` dict → write via `AnyEncodable` wrapper (avoids envelope duplication)
- Android serialization: call `event.toJson()` → patch `timeseries.data` field in resulting `JsonObject` (reuses generated serialization)
- Encoder types: all scaled values as `Int64` (Swift) / `Long` (Kotlin) — enforced by type signature to prevent overflow for large `memory_max` values
- Size comparison log: `#if DEBUG` guarded on iOS, debug build check on Android — zero overhead in release builds
- Encoder location: iOS → `DatadogRUM/Sources/Timeseries/`, Android → same package as collector
- Tests: encoder unit tests + collector flush output tests (both modes)

## Tasks

### iOS
1. `DeltaEncoder.swift` — pure static `encodeMemory(_:precision:)` and `encodeCPU(_:precision:)` returning `[String: Any]?` (nil for ≤1 sample)
2. `DeltaTimeseriesEvent.swift` — `DeltaTimeseriesMemoryEvent` and `DeltaTimeseriesCpuEvent` Encodable structs with full RUM envelope + delta data field
3. Add `enableDeltaCompression: Bool = false` to `TimeseriesSessionCollector.init`
4. `flushMemory()` — branch on flag: call encoder, drop if nil, write `DeltaTimeseriesMemoryEvent`, log size
5. `flushCPU()` — same pattern
6. `DeltaEncoderTests.swift` — 3-sample batch assertions: ts[0] absolute, ts[1..2] deltas, fields scaled + delta'd
7. `TimeseriesSessionCollectorTests.swift` — delta mode cases: JSON shape assert, single-sample drop

### Android
8. `DeltaEncoder.kt` — `encodeMemory(buffer, precision): JsonObject?` and `encodeCpu(buffer, precision): JsonObject?`, null for ≤1 sample
9. Add `enableDeltaCompression: Boolean = false` to `TimeseriesSessionCollector` constructor
10. `flushMemoryBatch()` — branch on flag: encoder, skip if null, manual `JsonObject`, write, log
11. `flushCpuBatch()` — same
12. `DeltaEncoderTest.kt` — same assertions, Kotlin style
13. `TimeseriesSessionCollectorTest.kt` — delta mode cases

### Wrap-up
14. iOS linter + tests (`DatadogRUM iOS`)
15. Android tests (`TimeseriesSessionCollectorTest`)
16. Export pantry notes (`/nono:export --timeseries`)

## Verification Strategy
1. **Unit tests** — `DeltaEncoderTests` with known 3-sample batches, exact Int64 delta assertions. Collector flush tests with `enableDeltaCompression=true` assert delta JSON shape and single-sample drop. Runs automatically via `make test-ios SCHEME="DatadogRUM iOS"` and Android test suite.
2. **Instrumented size logs** — Enable flag locally, run sample app for ~1 min, confirm `[Timeseries] delta flush:` lines appear in console with `ratio > 1x`.
3. **Staging event inspection** — Capture raw intake payloads in staging, confirm `timeseries.data` is the columnar delta object (not an array).

## Status
- [ ] Phase 3: Criticism
- [ ] Phase 4: Verification strategy
- [ ] Phase 5: Implementation
- [ ] Phase 6: Verification
- [ ] Phase 7: Report
