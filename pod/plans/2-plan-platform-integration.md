# PLAN.md — Platform Integration Wiring (Plan 2)

**Date:** 2026-04-14
**Epic:** RUM-13949
**Pod:** AI-first Performance Timeseries
**Author:** Barbora Plasovska

---

## Purpose

This plan tells an agent how to wire the Plan 1 business logic into any SDK platform (iOS, Android, React Native, etc.). It is **platform-agnostic** — described in prose with hints. The agent is told "implement Plan 2 for [platform]" and figures out the platform-specific code.

### Relationship to Plan 1

- **Plan 1** = standalone business logic (batcher → builder → encoder). Produces RUM timeseries JSON events from timestamped samples. Verified with CSV input → JSON output exact match.
- **Plan 2 (this plan)** = wire Plan 1's logic into a real SDK. Read real metrics, run on a timer, plug into the session lifecycle, send output to the upload pipeline.

Plan 1 is a **reference implementation**, not a library to import. The agent must:
- Read `plans/1-plan-business-logic.md` for architecture and design decisions
- Read `DatadogTimeseries/` source code for exact logic (batcher, builder, encoder, timestamp handling)
- **Rewrite** the logic into the target SDK's code style, module structure, and conventions
- Event models must come from the SDK's own model generation system, not copied from Plan 1

After Plan 2 is implemented for a platform:
- Remove the `DatadogTimeseries/` standalone package from the repo — it was a validation tool, not a permanent artifact
- Move the test fixtures (CSV input, expected JSON) into the platform SDK's test directory

---

## Decisions Log (carried from Plan 1 + IPCIVR)

### Design decisions from Plan 1 (must be followed)

| Decision | Detail |
|----------|--------|
| Batcher is metric-agnostic | One batcher per metric, it just accumulates samples. Metric name is assigned by the builder, not the batcher. |
| Event builder owns metric name | Builder receives `metricName` when building an event. Batcher doesn't know what metric it's batching. |
| `date` field = first sample timestamp in ms | `start` timestamp (nanoseconds) divided by 1,000,000. |
| Timestamps | Event-level `date` in milliseconds. Everything inside `timeseries` (start, end, data point timestamps) in nanoseconds. |
| `_dd.format_version` = 2 | Constant. |
| `session.type` = "user" | Constant for now. |
| `type` = "timeseries" | Constant. |
| Explicit CodingKeys / field mapping | All JSON keys are snake_case. No automatic conversion — explicit mapping to avoid edge cases like `_dd`. |
| Two metrics for MVP | `memory_usage` and `cpu_usage`. Closed enum with documented extension path. |
| Skip failed samples | If a metric read fails, skip it (leave a gap). Don't crash, don't retry. |

### Plan 2 decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Reuse mode | Rewrite into SDK | Plan 1 is reference. Agent rewrites using SDK patterns and conventions. |
| Plan structure | 3 phases | (1) Metrics flowing, (2) Session lifecycle, (3) Upload pipeline. Each independently verifiable. |
| Detail level | Requirements + hints | State what to achieve, add hints like "look at VitalReaders" to point the agent in the right direction. |
| Verification | Integration tests with mocks | Mock boundaries, trigger manually, verify JSON output. Follow SDK's existing test patterns. |
| Background handling | Future concern | Not addressed in Plan 2. MVP: collect only while app is active. |
| E2E staging validation | Outside scope | Plan 2 stops at "JSON handed to upload pipeline". |
| Config flag | TODO, default opt-in | Add a config flag, default disabled. Decision pending, easy to flip. |
| Fixtures after removal | Move to platform tests | Copy CSV/JSON fixtures from Plan 1 into the SDK's test directory. |

---

## TODO Placeholders (blocked decisions)

These are not yet decided. Implement with the stated defaults; they are designed to be easy to change.

| Item | Default | What might change | Impact of change |
|------|---------|-------------------|-----------------|
| Schema | Current staging schema (numeric-only `data_point_value`) | Polymorphic value schema (A/B/C) — waiting on William/backend results | Event model struct changes. Regenerate from `rum-events-format`. |
| Batch size | 30 (30 seconds at 1Hz) | Backend may recommend different size | One constant to change. |
| Collection interval | 1 second | Could change based on performance feedback | One constant to change. |
| Config flag default | `false` (opt-in) | Team may decide always-on | One boolean default to flip. |

---

## Phase 1 — Get metrics flowing

### What to do

1. Find the SDK's existing metric/vital readers for memory and CPU
2. Create a collector component that:
   - Runs a 1-second periodic timer on a background thread
   - Each tick: reads memory and CPU from the existing readers
   - Creates a `Sample(timestamp_nanoseconds, value)` for each metric
   - Feeds each sample into a batcher (one batcher per metric, metric-agnostic)
   - When a batcher is ready to flush (buffer >= batch size), builds a timeseries event via the builder and encodes it to JSON
3. If a metric read fails, skip it (leave a gap in the data). Do not crash or retry.

### Hints

- Look for existing periodic collection patterns in the SDK (e.g. vital readers, performance monitors). Follow the same threading, timer, and lifecycle patterns.
- If no existing metric collection pattern exists, create a minimal background timer that reads metrics and feeds the pipeline. Keep it simple.
- The timer should not block the main thread. Buffer access must be thread-safe.

### Done when

- A test exists that: mocks the metric reader to return known values, triggers collection manually (no real timer wait), and verifies that correctly-shaped JSON events are produced.
- The JSON output matches the expected structure from Plan 1 (same fields, same timestamp precision, same constants).

---

## Phase 2 — Add session lifecycle

### What to do

4. Wire the collector to the RUM session lifecycle:
   - **Start** collecting when a new RUM session begins
   - **Stop** collecting when the session ends (timeout, max duration, or explicit stop)
   - **Flush remaining** on stop: flush any samples left in both batchers, even if below batch size. Don't lose the tail.
5. On session renewal (old session ends, new one starts): stop old collector, create new one. No gap, no overlap.

### Hints

- Look for the session scope/manager in the SDK. Look at how other session-scoped components are created and destroyed. Follow the same pattern.
- Look at how the SDK handles session timeout (e.g. 15 min inactivity) and max session duration (e.g. 4 hours). The collector should respond to the same signals.

### Done when

- A test exists that: simulates session start → collection → session stop, and verifies that (a) events are produced during the session, (b) remaining samples are flushed on stop, (c) no events are produced after stop.

---

## Phase 3 — Connect to upload pipeline

### What to do

6. Hand the encoded JSON events to the SDK's existing event writer/upload pipeline
7. The events should flow through the same path as other RUM events (storage → upload → backend)
8. Add a configuration flag to the SDK's RUM configuration (default: disabled / opt-in). When disabled, the collector is not created.

### Hints

- Look at how other RUM event types (views, actions, errors) are written to the pipeline. Follow the same writer pattern.
- For the config flag, look for existing boolean feature flags in the RUM configuration (e.g. `trackFrustrations`, `trackBackgroundEvents`). Follow the same pattern.

### Done when

- A test exists that: enables the config flag, starts a session, triggers collection, and verifies that events reach the writer/upload layer (mocked at the writer boundary).
- The config flag defaults to disabled. When disabled, no collector is created, no timer runs, no overhead.
- All existing SDK tests still pass (no regressions).

---

## Verification Strategy

### What to test

1. **Phase 1**: Given known metric values → collector produces correctly-shaped JSON events
2. **Phase 2**: Session start triggers collection, session stop flushes and stops, no events after stop
3. **Phase 3**: Events reach the upload pipeline, config flag gates the feature, no regressions

### How to test

- Mock the metric readers to return deterministic values
- Trigger the timer/collection manually (inject a manual trigger instead of waiting for real seconds)
- Mock the writer to capture output and verify it
- Look at how existing collectors/features are tested in the SDK. Follow the same mocking approach and test utilities.
- Copy Plan 1's test fixtures (CSV input, expected JSON) into the platform's test directory for reference

---

## How to use this plan

```
Agent prompt:

"Implement Plan 2 for [iOS / Android / React Native].

1. Read plans/1-plan-business-logic.md for design decisions
2. Read DatadogTimeseries/ source code for exact business logic
3. Read this plan (plans/2-plan-platform-integration.md) for integration steps
4. Explore the target SDK to find existing patterns for:
   - Metric/vital readers (memory, CPU)
   - Periodic collection (timers, background threads)
   - Session lifecycle (scope/manager, start/stop signals)
   - Event writing (how RUM events reach the upload pipeline)
   - RUM configuration flags
   - Test patterns (mocking, test utilities)
5. Implement the 3 phases in order, following TDD
6. After implementation: remove DatadogTimeseries/ standalone package, 
   move test fixtures to the platform's test directory"
```
