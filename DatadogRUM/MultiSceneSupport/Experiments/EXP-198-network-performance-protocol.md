# S1:E01 URLSession performance and retention qualification

Status: EXP-198 protocol admitted before fixture implementation or measurement; candidate/ownership amendment after EXP-199, before any accepted ABBA. Prepared 2026-09-20. This qualifies the isolated E01 preparation/resume/callback change, not the deferred scene-routing implementation or a release.

## Frozen comparison and thresholds

A is develop `62f64d7b655bdc83f3036c4ad81090a270f6202b`. B is frozen local commit `1bdc9286c17d69d73e5e41530e6179c72a723368`, the exact baseline plus the approved three-file E01 delta and its EXP-199 terminal-ownership repair. The commit is unsigned under the user-authorized fallback after signing-agent communication failed; no push is authorized. The appended identity inventory hashes only those three production files. Before building, freeze the complete allowed source archive and verify that no additional production differences enter B. Use one identical fixture in both arms; do not copy the historical candidate's scene-routing fixture or change the historical BASELINES.md.

Preserve BASELINES.md:35–59 budgets, applied independently to each admitted URLSession dispatch row:
- Median increase <= max(10% of A median, 500 ns/dispatch); p95 increase <= max(20% of A p95, 1,000 ns/dispatch).
- Allocation excess <= max(5% of A, 1 successful heap allocation/dispatch) AND <= max(5% of A, 64 requested bytes/dispatch). Report all row denominators. Full-task allocation rows use one task, never the number of internal callbacks, as their denominator.
- After 20 discarded warm-up task lifetimes: candidate live-heap growth for the first 100 <= 65,536 bytes; the next 100 adds <= 16,384 bytes. Zero surviving task/interception/feature weak references and zero remaining task-owned records at their defined teardown boundaries.
- No threshold increases, pooled fast-path offsets, deletion of unfavorable samples, or substitution of RSS/live bytes for allocation churn. Missing instrumentation/coverage is INCONCLUSIVE.

Use Release -O, Swift 5, ENABLE_TESTABILITY=YES, the same exact Xcode/build SDK/architecture/destination in A and B, and minimum deployment15. Copy the generated-project/source-archive machinery; never open/copy local xcconfigs or repository project files.

For a finite S1 qualification, freeze two runtime rows before execution: the root's qualified 27.x runtime and its already-used 17.5 runtime. Record exact runtime builds and destination identities. This is a new S1 projection; it does not alter or rerun historical EXP-160's 27.0/26.5 rows. If a required row is unavailable, report the missing row, not a substituted PASS. No iOS15/16, watchOS, physical-device, Duo, or whole-app throughput claim follows from these simulator rows.

## Smallest fixture and measurement matrix

Use a generated single-scene app solely as the process host. The component fixture constructs the real NetworkInstrumentationFeature using NetworkContextCoreProvider and its existing initializer, installs a small non-retaining DatadogURLSessionHandler, and calls feature.bind(configuration:nil). Registered mode additionally binds an actual fixture URLSessionDataDelegate class. No RUM manual-event loop can qualify E01.

Use real URLSession tasks from an ephemeral session. A fixture URLProtocol accepts only a fixed task URL namespace, has no external traffic, and can hold transport after startLoading. Configure one deterministic first-party header mutation; count mutations, starts and completions using preallocated scalar storage, without retaining interceptions/tasks/errors/bodies. Automatic mode uses dataTask completion handlers. Registered mode uses its real delegate, four fixed 256-byte chunks, and normal task metrics/completion. Input URL, body, headers, delegate behavior and mode are identical across arms.

Run one complete ABBA quartet for each tracking mode and instrument mode:
- Tracking: automatic; registered delegate with the prerequisite automatic binding.
- Instrument mode: timing; allocations plus retention.
Thus 16 fresh launches per runtime, 32 for the two-runtime projection. A/B/B/A order is recorded per quartet. Build everything before any accepted quartet; root must hold all other build/test/profile activity during its measurement window.

Timing processes never install the allocation logger. Each timing row gets one discarded 1,000-operation warm-up, seven measured 1,000-operation batches, and 2,000 individual dispatch samples per process. These new workload sizes are fixed here before measurement; the old runner's 20,000-operation validator must not silently validate this new schema. Each operation prepares its task/input outside the timed range. Bound outstanding native tasks to 64, settle between chunks, and preserve raw samples and batch means. Preallocate sample storage.

Measure separate rows, never an averaged mixture:
1. SDK-unbound first native task.resume(), as an A/A process/transport control.
2. First resume with automatic or registered instrumentation: actual task.resume() through the production swizzle, synchronous preparation and original implementation.
3. A second resume while the same task is ready and transport remains held: exercises existingResumeAction/ready forwarding. Record baseline repeated mutation as the known old behavior; do not treat its extra work as a credit against row 2.
4. Data, metrics, completion, and state callback dispatch as individually named rows. Use real already-resumed tasks with native transport held, enter the existing feature.task(...) methods that the production callback swizzles invoke, and drain afterward. No mocked reimplementation of route/enqueue. A fresh intercepted task is used for each destructive completion/completed-state sample. Registered rows supply the required companion metrics/completion outside the timed range. Label these controlled callback-entry microbenchmarks, not real network latency.

For rows 2–4 record caller entry-to-return and, in a separate loop, entry through an immediate feature.flush(); keep the caller on a non-feature-queue thread. Apply the unchanged ordinary dispatch budget to both named timing boundaries. For callback-entry rows, native transport is already held/quiescent, so the queue barrier closes the controlled SDK operation. For first resume, explicitly label the second boundary "resume through immediate feature flush (already-enqueued SDK work)": native running-state interception may enqueue afterward. Await held startup plus a final flush outside that timer; never describe the prefix as fully settled or SDK-only total latency. Native startup/end-to-end latency may be recorded separately as diagnostic evidence only. For process-wide first-resume allocation windows, await held startup before the final flush and epoch close, and label the scope as including native startup allocations. This retains all rows, thresholds and sample counts while making the timing and allocation boundaries explicit before accepted samples.

Before accepted samples, execute a small untimed native round trip in each tracking mode, including actual swizzled completion/delegate/state callbacks. Require exactly one prepared header at URLProtocol, one start and completion per ordinary task, correct body length, and registered metrics present. Record stage counters and task identity. This attests real transport/callback reachability in addition to the controlled callback rows.

Preparation-only branches get bounded, untimed qualification controls using the existing E01 test patterns: synchronous repeated resume from modify; cancellation/early callback during preparation; registered >512 KiB discard; automatic full body preservation; completed-task resume; and all-unhandled forwarding. These are not new performance claims or a reopening of the already-frozen correctness suite. A fixture-only probe can reflect preparing/ready records and weak terminal identity outside timing. Never use an instrumentation hook to replace the code being measured.

## Allocation churn and asynchronous coverage

The checked-in AllocationCounter.c:13–21 records only the installation pthread. The old TLS-style/fixed-thread result MUST be labeled caller-thread only. It misses allocations in the serial feature queue and CFNetwork/delegate workers; queue identity is not a permanently assigned pthread.

Smallest sufficient extension, fixture only:
- Keep malloc_logger's successful-allocation/requested-byte semantics and occupied-logger refusal.
- Add lock-free atomic process totals and a separate caller-thread bucket, with a preallocated callback that performs no Swift work, heap allocation, stack capture, dispatch lookup, or dynamically initialized TLS. Check lock-free availability before installing. Read/reset only with a closed measurement epoch; callback state must be race-free.
- Other-thread = process total minus caller bucket. This is an other-thread bucket, NOT an SDK-queue attribution. Process totals cover successful heap allocation operations during the bounded window, including unrelated in-process work; they exclude VM allocation and are not an SDK-only stack attribution.
- Keep timing entirely in separate uninstrumented processes.
- Preserve malloc(17), calloc(3,19), realloc(...,91) -> exactly 3 operations / 165 requested bytes. Validate on the caller first.
- Repeat the same sentinel from an actual asynchronous block on the reflected feature queue, proving it ran on a different pthread. Require the sentinel in process totals/other-thread bucket and absent from caller-only counts. Dispatch enqueue/setup happens outside the sentinel epoch. A sync block may execute on the caller and is not this discriminator.
- Run an isolated background-worker sentinel similarly. An intentionally caller-only collector must fail asynchronous-coverage admission. Concurrent-epoch calibration must prove no lost counts. Unexpected activity makes calibration INCONCLUSIVE; do not subtract it until calibration "passes".

Use identical, allocation-free interval bookkeeping and serialized measurement windows. For callback rows, start immediately before the real feature.task(...) call and stop only after feature.flush(); native transport is held and all other callback sources are quiescent. For complete task cycles, count from first resume through observed native completion/delegate invalidation and the final feature flush; report process/caller/other totals per task. Task/session creation is separately labeled and outside the dispatch window, and is included in a separate full-lifetime churn diagnostic. Do not sum caller counts into process totals again.

Run one discarded allocation batch and seven measured 1,000-operation batches per row. Store counts and requested bytes before producing JSON or other result objects. Apply allocation limits to the individual dispatcher rows and full-task totals; use no averaging across rows. Retain raw both-arm observations and fixed-duration idle/control windows as noise diagnostics, not an automatic subtraction.

If the atomic all-thread observer cannot be safely calibrated, retain the caller-only evidence as partial and use an independently qualified Allocations capture/export for the missing threads. Until that works, asynchronous allocation qualification remains INCONCLUSIVE. xctrace's executable exists locally, but its usable Allocations template, export schema and allocation-stack attribution were not exercised in this design task.

## Task/feature retention and 20+100+100 retained bytes

Use one long-lived feature per tracking mode and exactly 220 task lifetimes. Each cycle makes a real task, performs resume/preparation plus terminal callback handling, invalidates its ephemeral session, waits for the delegate invalidation receipt, drains the feature from outside its queue, exits the autoreleasepool, and drops fixture references. The receiver records scalar receipts only. Reuse fixed-capacity weak slots/counters; no observation array may grow with the cycle count.

At each cycle, preserve a temporary strong task through completion and verify the candidate retains only weak terminal identity and no preparation value or buffered continuations/events; repeated completed-task resume must not mutate/start again. Then release the task/session. This intentionally repeats the known baseline bug in a separately labeled discriminator; do not fold its baseline orphan allocations into ordinary performance samples. For the numeric 220-lifetime series use the ordinary one-resume lifecycle in BOTH arms, with identical terminal callback inputs.

At boundaries after 20, 120 and 220 cycles:
- Collect malloc_zone_statistics live bytes only after callback receipts, queue drains and autorelease pools. Read numeric heap values before allocating snapshots/JSON.
- Check weak tasks and weak interceptions: zero. Ensure fixture delegates/completion closures hold no task/feature.
- Inspect all directly task-owning feature collections, including interceptions and truncatedInterceptions; candidate additionally has preparations and the weak terminalTasks identity set. Discover unexpected additional owning collections instead of relying only on a whitelist.
- For preparations record raw NSMapTable count before enumeration, live weak keys, remaining values, and phase/continuation/event counts. Observation must not remove/clear entries. Weak-key disappearance alone is insufficient if terminal values/payloads remain. Capacity/allocator storage is reported separately in live bytes, not treated as a live task.
- Require no remaining live task members or preparation/payload/continuation records after released-task teardown. Dead weak slots/capacity may remain and are not a live-task count; they remain visible in numeric heap measurements. Preserve raw versus enumerated results so a lazy weak-table sweep is visible rather than a hidden cleanup step.
- Require candidate first-100 and second-100 absolute retained-byte deltas within 65,536 and 16,384. Also show A's identical deltas and B-minus-A diagnostically. A's growth does not relax B's fixed limits.

After the 220-lifetime series, release the feature/provider/handler and any reflection temporaries outside an autoreleasepool and after the final drain. Require weak feature/provider/handler release. Verify SDK swizzling restored by exact previous-IMP identity or the existing independently qualified forwarding oracle. A fresh unrelated task must still execute its native path once. No fixture-owned collection may keep the feature alive.

Retain bounded negative controls outside accepted numeric samples: hold one task/feature deliberately -> weak/ownership oracle fails; retain a terminal payload/continuation -> collection oracle fails; and synthetic retained-byte growth exceeding each budget -> evaluator fails. Do not deliberately patch shipping SDK source for these controls.

This series qualifies task lifetimes under a retained feature plus its final release. It does not claim 220 SDK enable/disable lifetimes, genuine scene teardown, SwiftUI host teardown, or full-process leak freedom.

## Exact insertion points and implementation recipe

Work only in a fresh attempt's runner/Fixture copies:
- run.py:19–21 pins/archive paths; prepare:64–91 builds allowed source snapshots. Set A to develop62f64. Snapshot B from that base plus ONLY the approved three source files, then hash the complete allowed source inventory. The current stock runner cannot select these arms through CLI flags.
- run.py:99–114 supplies Release builds; 133–181 supplies clean launch/run-ID/binary checks; 247–250 supplies ABBA order. Extend explicit tracking/instrument arguments, runtime identities, row schema and cleanup; preserve invalid attempts and shutdown restoration.
- App.swift:99–125 supplies launch-mode dispatch/result output. Insert e01 modes before RUM/navigation configuration, with no EventStore/manual marker loop and no old InternalFixture scene calls.
- New copied Fixture/URLSessionE01Fixture.swift: @testable DatadogInternal; NetworkContextCoreProvider; NetworkInstrumentationFeature initializer at candidate:109; handlers; bind:129; public real URLSession task APIs; callback entry points:681/710/750/820; flush:898. A local wrapper can expose the reflected queue only for calibration and serialized diagnostic inspection. No production visibility change.
- AllocationCounter.c:13–43 / .h: extend observer in the temporary fixture only as above.
- New evaluator copied beside analyze.py:39–72,127–150: retain formulas, change explicit row/sample schema, enforce complete ABBA, caller/async coverage and owner/heap controls. Do not make the old EXP-160 analyzer accept missing handoff rows as a new PASS.

After fixture implementation, root alone runs the following shape; paths/modes below are the proposed generated fixture interface, not commands claimed available today:
```sh
DEVELOPER_DIR=/Applications/Xcode_27.1.app/Contents/Developer \
  xcodebuild build -project "$E01_ATTEMPT/baseline/E01.xcodeproj" -scheme E01 \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$E01_ATTEMPT/baseline/derived" CODE_SIGNING_ALLOWED=NO
DEVELOPER_DIR=/Applications/Xcode_27.1.app/Contents/Developer \
  xcodebuild build -project "$E01_ATTEMPT/candidate/E01.xcodeproj" -scheme E01 \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$E01_ATTEMPT/candidate/derived" CODE_SIGNING_ALLOWED=NO
# Adapted run_one performs terminate, uninstall + absent-container verification,
# install + binary identity, then this launch in recorded A/B/B/A order:
DEVELOPER_DIR=/Applications/Xcode_27.1.app/Contents/Developer \
  xcrun simctl launch --console "$E01_DEST" "$E01_BUNDLE" \
  --mode e01-timing --tracking automatic --run-id "$E01_RUN_ID"
# Repeat for registered tracking and e01-alloc-retention, then the second runtime.
# Rehash allowed sources, fixture, generated package and binaries; evaluate all
# required rows; clean every fixture and restore prior simulator shutdown states.
```

The root may substitute its already-qualified exact Xcode path before freezing the manifest; both arms must use it unchanged. Do not execute the stock historical `run.py all`: it pins the wrong revisions and exercises scene/manual-event paths.

## Admission and finite scope

Accepted numeric evidence requires completed source/binary identities, complete paired order, exact operation/callback receipts, calibrated thread coverage, no competing root workload, and all required rows present. Failure is FAIL; insufficient or invalid evidence is INCONCLUSIVE. A/A environment-control failure invalidates its paired window. All raw samples/failed attempts remain separate and preserved.

No source in this E01 delta adds scene handoff. Therefore the 5/10 microsecond enabled-scene-handoff budget and scene/controller/SwiftUI registry work are NOT APPLICABLE to S1:E01, with that source exclusion recorded. The task/feature lifetime analogue and ordinary dispatch/allocation budgets do apply. Historical deferred-scene gates retain their own statuses. Ordinary UIKit/SwiftUI, oldest-runtime compatibility, physical Duo and release evidence stay with their separately owned work.

Current qualification boundary: the all-thread counter passes caller, actual feature-queue, worker and concurrent sentinels on17.5. The remaining row fixture is being reviewed and has no accepted measurements. The initial retention fixture exposed a real terminal-record defect repaired by EXP-199, plus independent unbound/zero-body heap growth that remains unattributed. Numeric budgets stand; no ABBA or allocation/latency pass is claimed. Runtime/toolchain/device identities must come from fresh preflight.

## Inspected production source identities

```json
{
  "DatadogInternal/Sources/NetworkInstrumentation/NetworkInstrumentationFeature.swift": "2631ea56885a12d1b3d14b1044dd9a84319a0b382b817afb95b4edd305df5246",
  "DatadogInternal/Sources/NetworkInstrumentation/URLSession/NetworkInstrumentationSwizzler.swift": "a00edec0d9451c3b78c52f308c2a7f771d0e8b9cfafada79a2848f1b164cfef7",
  "DatadogInternal/Sources/NetworkInstrumentation/URLSession/URLSessionTaskSwizzler.swift": "96d302999632cc609a98e774106f1e51c4ef9fecfe089287426285aa524e4570"
}
```

## Candidate and ownership amendment

The original464af911 protocol remains in Git at `cfecc08d45fb0aa36a548ed81d1461527b4f6e14` for this same path (SHA256 `d94d439cf3ebca860236d0974097e2483b41b2b9e0f5b526e5b1f0747dbe0a3b`). EXP-199 demonstrates and repairs a strong terminal-value retention defect. This amendment changes only B and the terminal-record oracle to match that repair. Keep every timing/allocation row, boundary, sample count, ABBA order, absolute memory threshold, negative control and failed diagnostic. No accepted numeric measurement predates this amendment.
