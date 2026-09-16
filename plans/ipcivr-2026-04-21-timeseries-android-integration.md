# IPCIVR Plan — Android Timeseries SDK Integration (2026-04-21)

## Goal

Wire memory + CPU timeseries collection into the Android RUM session lifecycle, mirroring iOS Plan 4.
Collects samples at 1s intervals, batches 30 samples, writes `RumTimeseriesMemoryEvent` /
`RumTimeseriesCpuEvent` to the RUM feature scope on `bplasovska/feature/timeseries`.

## Decisions

- Self-contained `TimeseriesSessionCollector` inside `dd-sdk-android-rum` (not reusing DatadogTimeseries module — that was a pipeline testbed)
- CPU % via `/proc/self/stat` delta between consecutive 1s ticks, injectable via `cpuUsageProvider: (() -> Double?)?` lambda for test isolation
- Memory via `MemoryVitalReader.readVitalData()` (already returns bytes as Double)
- Models generated from `bplasovska/timeseries` branch on rum-events-format
- `enableTimeseries: Boolean = false` opt-in flag in `RumConfiguration`; also requires `vitalsUpdateFrequency != null`
- Session hook: `collector.start()` in `renewSession()` / initial tracked state; `collector.stop()` in `stopSession()`
- Dedicated `ScheduledExecutorService` via `sdkCore.createScheduledExecutorService("rum-timeseries")`; `shutdownNow()` + `NoOpScheduledExecutorService()` on stop
- `synchronized` blocks for buffer thread safety (SDK convention)
- `EventType.DEFAULT` for event writing
- Android `RumSessionType` only has `USER` / `SYNTHETICS` (no `CI_TEST`)

## Task List

### Step 0 — Model generation
- Add timeseries schema mappings to `features/dd-sdk-android-rum/generate_rum_models.gradle.kts`
- Run: `./gradlew :features:dd-sdk-android-rum:generateRumModelsFromJson -Pdd.rum.schema.ref=bplasovska/timeseries`
- Models land in `build/generated/json2kotlin/` — NOT committed to source (build-time generation)
- Add `TIMESERIES_BUILD.md` in the module root documenting the required flag for anyone building this branch
- **Must run this step before writing any code that references the generated classes**

### Step 1 — TimeseriesCollecting interface
- New file: `features/dd-sdk-android-rum/src/main/kotlin/com/datadog/android/rum/internal/timeseries/TimeseriesCollecting.kt`
- Methods: `fun start(sessionId: String, applicationId: String, sessionType: RumSessionType)` + `fun stop()`

### Step 2 — TimeseriesSessionCollector
- New file: `features/dd-sdk-android-rum/src/main/kotlin/com/datadog/android/rum/internal/timeseries/TimeseriesSessionCollector.kt`
- Constructor: `memoryReader: VitalReader`, `writer: DataWriter<Any>`, `sdkCore: SdkCore`, `batchSize: Int = 30`, `samplingIntervalMs: Long = 1000`, `cpuUsageProvider: (() -> Double?)? = null`
- Default `cpuUsageProvider`: reads `/proc/self/stat` delta using `existsSafe()` / `readTextSafe()` helpers + `Os.sysconf(_SC_CLK_TCK)` for normalization
- **Pre-warm CPU in `start()`**: read `/proc/self/stat` once at end of `start()` to set `prevCpuTicks` — first 1s tick then has a valid delta (no wasted sample)
- `ScheduledExecutorService` via `sdkCore.createScheduledExecutorService("rum-timeseries")` — new executor created on `start()`, `shutdownNow()` + replaced with `NoOpScheduledExecutorService()` on `stop()`
- Memory buffer + CPU buffer, flush at `batchSize = 30` or on `stop()`
- Write via `DataWriter<Any>.write(event, null, EventType.DEFAULT)`
- **Thread safety**: `synchronized(this)` wraps the entire `sample()` body, `flushMemory()`, `flushCPU()`, and the flush calls inside `stop()` — prevents race between in-flight sample and stop flush

### Step 3 — RumSessionTypeExt
- Add `fun RumSessionType.toTimeseriesMemory(): RumTimeseriesMemoryEvent.Session.Type` in `RumSessionTypeExt.kt`
- Add `fun RumSessionType.toTimeseriesCpu(): RumTimeseriesCpuEvent.Session.Type` in `RumSessionTypeExt.kt`

### Step 4 — Serializer registration
- Add two `is` branches in `RumEventSerializer.serialize()` (the existing `when` expression):
  - `is RumTimeseriesMemoryEvent -> model.toJson().toString()`
  - `is RumTimeseriesCpuEvent -> model.toJson().toString()`
- No separate registration infrastructure needed — generated models already have `toJson()` from the GSON-based code generator

### Step 5 — RumConfiguration flag
- Add `enableTimeseries: Boolean = false` to `RumConfiguration` (or `Rum.Configuration`)

### Step 6 — RumFeature factory
- Create collector only when `enableTimeseries = true` and `vitalsUpdateFrequency != null`
- Create dedicated executor `"rum-timeseries"`
- Pass collector to `RumScopeDependencies`

### Step 7 — RumSessionScope hookup
- **ALL session starts go through `renewSession()`** — confirmed from code: even the first session (isNewSession=true) calls `renewSession()` with `USER_APP_LAUNCH`
- At the **top** of `renewSession()`: if `sessionState == TRACKED`, call `collector.stop()` (stops previous session before renewing)
- At the **bottom** of `renewSession()`: if `keepSession == true`, call `collector.start(sessionId, applicationId, sessionType)`
- In `stopSession()`: call `collector.stop()`
- Guard all calls with null check; `stop()` must be idempotent (safe to call twice)

### Step 8 — Unit tests
- New file: `features/dd-sdk-android-rum/src/test/kotlin/com/datadog/android/rum/internal/timeseries/TimeseriesSessionCollectorTest.kt`
- Use Mockito `@Mock lateinit var mockMemoryReader: VitalReader` and `@Mock lateinit var mockWriter: DataWriter<Any>`
- Mirror 7 iOS test cases: batch flush memory, batch flush CPU, partial flush on stop (memory), partial flush on stop (CPU), nil readers write no events, session restart uses new metadata, timestamps monotonically increasing
- Injectable `cpuUsageProvider` lambda for fixed CPU values

### Step 9 — Forgery factory
- New file: `features/dd-sdk-android-rum/src/testFixtures/kotlin/com/datadog/android/rum/utils/forge/TimeseriesEventForgeryFactory.kt`

## Key file paths

| Purpose | Path |
|---------|------|
| Collector | `features/dd-sdk-android-rum/src/main/kotlin/com/datadog/android/rum/internal/timeseries/TimeseriesSessionCollector.kt` |
| Interface | `features/dd-sdk-android-rum/src/main/kotlin/com/datadog/android/rum/internal/timeseries/TimeseriesCollecting.kt` |
| Session scope | `features/dd-sdk-android-rum/src/main/kotlin/com/datadog/android/rum/internal/domain/scope/RumSessionScope.kt` |
| RumFeature | `features/dd-sdk-android-rum/src/main/kotlin/com/datadog/android/rum/internal/RumFeature.kt` |
| SessionTypeExt | `features/dd-sdk-android-rum/src/main/kotlin/com/datadog/android/rum/internal/RumSessionTypeExt.kt` |
| Model generation config | `features/dd-sdk-android-rum/generate_rum_models.gradle.kts` |
| VitalReader helpers | `dd-sdk-android-core/src/main/kotlin/com/datadog/android/core/internal/persistence/file/FileExt.kt` |
| NoOpExecutor | `features/dd-sdk-android-rum/src/main/kotlin/com/datadog/android/rum/internal/thread/NoOpScheduledExecutorService.kt` |

## Verification strategy

- `./gradlew :features:dd-sdk-android-rum:test` — all unit tests pass
- Manual RocketLauncher (Android) run with `enableTimeseries = true` to confirm events reach backend
