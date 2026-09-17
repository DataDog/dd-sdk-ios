# Early compatibility and performance baseline

Protocol fixed before EXP-160 implementation or measurement on 2026-09-17.
Gates: C01–C06 and P01–P04. These early measurements precede further telemetry
API expansion; repeat at release freeze and after a relevant architectural change.

## Comparison

- Baseline: `92f021ba7e4a866f84a52da93ed8b63f3dc75882`, the parent of the
  first scene-routing commit `ff37d7154`, release 3.17.0 merge.
- Candidate SDK: `af63657f08dbecb66e7c3ae97ed53fc8f7b065b9`, accepted EXP-159.
- Use isolated checkouts and one identical, recorded fixture; no edits to the
  user's checkout/project/configuration. Generated fixture projects and derived
  data live under a fresh attempt directory. Never copy local credentials.
- Same Xcode 27 toolchain, architecture, destination, Release optimization and
  workload for each pair. Use ABBA order, at least five measured batches per arm,
  discard an explicit warm-up batch. Preserve every sample and environment.
- iOS 27 plus available older supported iOS 26.5; minimum iOS 15 compilation is
  separate from runtime proof. No iOS 15 runtime is installed at definition time.
  Do not substitute a newer simulator for C06.

## Representative correctness workload

Ordinary UIKit single-scene automatic and manual apps must execute Home → Detail
→ fresh Home with actions/Resources on exact matching owners. Repeat in a legacy
UIApplicationDelegate app without a scene manifest, and on the older runtime.
Custom legacy-only monitors and NOP must preserve exactly-once forwarding/no-op
behavior; targeted tests can cover this seam independently of app launch.
No semantic multi-scene API is needed by these ordinary apps. View IDs differ
across revisions, so compare occurrence/name/count/owner relationships, not raw
UUID equality across separate processes.

## Predeclared acceptance thresholds

| Measure | Required result |
| --- | --- |
| Ordinary event dispatch | Candidate median increase ≤ max(10% of baseline, 500 ns/event); p95 increase ≤ max(20%, 1,000 ns/event). Record both SDK-disabled and SDK-enabled dispatch. |
| Enabled scene handoff | Additional median ≤ 5 microseconds/event, p95 ≤ 10 microseconds/event over the ordinary path; exact context restored after every nested dispatch. This is an early microbenchmark budget, not device-wide performance proof. |
| Allocation churn | Candidate excess ≤ max(5% of baseline, 1 allocation/event) and ≤ max(5%, 64 allocated bytes/event) for identical fixed dispatch workload. Measure allocations, not only resident or live heap bytes. |
| Retained scene state | Zero surviving SDK-owned scene/controller/host weak references and registry entries after teardown/drain. After warm-up, 100 repeated lifetime cycles retain at most 64 KiB; a second 100-cycle batch adds at most 16 KiB. Report allocator noise separately from ownership checks. |
| Reentrancy | Zero wrong-context, duplicate original-dispatch, unbalanced restore, deadlock, or crash across nested A → B → A and early-return paths. |
| Compatibility | Exact expected semantic relationships and event counts; zero SDK-caused crashes, cross-owner events, duplicate occurrences or custom/NOP forwarding differences. |

Thresholds are deliberately small absolute budgets combined with relative limits
to avoid unstable ratios near zero. They are not retroactively raised to accept
a result. A failure requires investigation and a gate disposition; unavailable
allocation instrumentation is INCONCLUSIVE, never a memory-baseline PASS.

## Measurement integrity

Record source revisions/fingerprints, fixture hash, app binary identity, complete
commands, raw samples, launch mode, OS/model, optimization and test results in a
machine-readable result. Instrumented allocation runs are separate from timing
runs. Use Allocations or an equivalent exact allocation counter; live malloc-zone
statistics alone describe retained heap and cannot establish allocation churn.
Custom/NOP or hostless lifetime tests do not replace ordinary-app runtime gates.
Use scoped reads and never inspect Datadog.local.xcconfig.

## Results

EXP-160 completed on 2026-09-17 against the pinned revisions above. The protocol
hash `c24f741f008e654e816f96ba418ed62225aa0ae1470582bd2c15fc789e113345`
and all original SDK source, main fixture and measured binary identities were
verified unchanged after execution. No threshold was raised.

Durable evidence: [gate results and identities](Results/EXP-160-baseline.json),
[raw numeric samples, calibration and sanitized local events](Results/EXP-160-baseline-samples.json),
and the [repeatable runner](../../tools/multi-scene/baselines/README.md).
Compiler/generator logs remain local diagnostic artifacts; the result records
all hashes and locations. Runtime console and complete crash reports are not
committed.

| Gate | Result | Decisive evidence and remaining limit |
| --- | --- | --- |
| C01 automatic single scene | PASS | Exact Home → Detail → fresh Home occurrences and action/Resource owners in both revisions on iOS 27 and 26.5. |
| C02 manual single scene | PASS | Same ordinary-app matrix with manual view instrumentation; exact owners and counts. |
| C03 legacy lifecycle | INCONCLUSIVE | iOS 26.5 navigation and real OS background/foreground pairs pass for automatic/manual apps. Both SDK revisions trap in UIKit's no-scene-lifecycle adoption check on iOS 27 before completion; four binary-UUID-matched excerpts are recorded. This is an environment limit, not an SDK regression conclusion. |
| C04 custom/NOP monitors | PASS | Eight focused launches preserve exact legacy forwarding and one nil NOP callback; the candidate's targeted action bridge also forwards exactly once on iOS 27. |
| C05 available older runtime | PASS | iOS 26.5 ordinary apps, legacy navigation/background/foreground and custom/NOP checks pass. |
| C06 minimum supported runtime | ENVIRONMENT BLOCKED | No iOS 15 runtime is installed. Both Release app variants compile/link with Mach-O minimum OS 15.0; this does not prove iOS 15 execution. |
| P01 dispatch overhead | PASS | All frozen median/p95 budgets pass in complete ABBA quartets on both runtimes; numerical comparisons below. |
| P02 allocation churn | FAIL | Ordinary filtered dispatch adds zero allocations. Enabled handoff adds **3 allocations and 416 requested bytes per event**, above the fixed **1 allocation / 64-byte** excess budgets, replicated in both candidate processes on both runtimes. |
| P03 retained scene state | FAIL | After 20 warm-up + 200 lifetimes, both `sceneActivityByIdentifier` and `disconnectedSceneIdentifiers` retain **220 entries** in every candidate run. Zero controller weak references survive. First 100-cycle live-heap growth is 31,072–47,472 bytes; second is 15,616 bytes. Heap budgets pass, but registry ownership fails. This posted-handler fixture does not establish real OS scene or mounted SwiftUI host teardown. |
| P04 reentrancy | PASS | Separately hashed assertion variant checks full `RUMCoreContext` equality and handoff fields across A → authoritative-nil B → A, early return, thrown B scope and final cleanup. Each runtime: 90,000 boundaries, 20,000 original dispatches, 10,000 caught throws, zero errors. No timed ABBA rerun was needed. |

The actual legacy background/foreground fixture emits a stopped Home and a fresh
Home for automatic tracking, and retains the same Home for manual tracking, in
both revisions. Its bounded pass does not dismiss other legacy lifecycle cases
or source-review findings.

All timing values below are **nanoseconds per event**, baseline → candidate.
Handoff rows compare the candidate's ordinary → enabled path. Each arm has two
fresh processes with a discarded 20,000-operation warm-up, fourteen measured
20,000-operation batch means in total, and 4,000 individual event samples.

| Runtime / workload | Median | p95 |
| --- | --- | --- |
| iOS 27, SDK disabled UIApplication dispatch | 12,708 → 12,500 | 15,542 → 15,291 |
| iOS 27, SDK enabled UIApplication dispatch | 12,959 → 12,750 | 15,875 → 15,917 |
| iOS 27, scene-bearing filtered touch | 166 → 333 | 167 → 416 |
| iOS 27, enabled handoff | 333 → 2,041 | 416 → 2,125 |
| iOS 26.5, SDK disabled UIApplication dispatch | 21,042 → 22,958 | 24,334 → 24,250 |
| iOS 26.5, SDK enabled UIApplication dispatch | 22,459 → 23,375 | 25,459 → 24,875 |
| iOS 26.5, scene-bearing filtered touch | 166 → 333 | 167 → 417 |
| iOS 26.5, enabled handoff | 333 → 2,000 | 417 → 2,500 |

Execution used Xcode 27 Release binaries on an Apple M4 Max host with arm64
simulators. Other task build/test/profile activity was held during the accepted
ABBA window. These are simulator microbenchmarks, not physical-device latency or
whole-application throughput measurements. Allocation recording follows timing
and counts successful heap allocations on the workload thread, with a required
3-operation / 165-byte malloc/calloc/realloc calibration; VM allocations and
other threads are outside that counter.

An initial generated-package Swift-language-mode error and a fixture-only
allocation-observer TLS recursion invalidated preliminary attempts. Their
identities and available samples are preserved separately. The corrected
fixture completed a new full ABBA series; those invalid attempts contribute no
accepted timing result. The evaluator's 11 negative-control tests pass, including
wrong ownership despite correct counts, missing/duplicate/reused occurrences,
p95 regression, incomplete ABBA, changed binary identity and insufficient
full-context checks.

## EXP-166 handoff repair

Signed SDK `5eb3c1aac` closes P02 after complete Release ABBA runs on iOS27/26.5
using copied EXP-160 workloads. Only owner-scoped SPI bindings differ; the
protocol above and original fixtures remain unchanged. Ordinary dispatch remains
0 allocations/0 bytes; enabled handoff is 1 allocation/64 requested bytes per event
in all four measured candidate processes, down from 3/416. All ordinary and
handoff median/p95 limits pass. Full-context reentrancy checks 90,000 boundaries
per runtime with zero errors; P01/P04 remain closed. The thread storage retains
no core/scene context after scope exit. P03's separate registry failure remains.

See [paired results](Results/EXP-166-handoff-performance.json) and
[numeric samples](Results/EXP-166-handoff-performance-samples.json). One-off
1/112 and1/64 diagnostics are retained separately and make no timing claim.
The unchanged scope remains simulator microbenchmarks, not device-wide proof.


### EXP-168 keyed host lifetime repair

Signed `7b77f60eb` supplies mounted SwiftUI evidence for the D03 dependency of
P03. With five warm-up plus twenty measured cycles on27/26.5, the unchanged SDK
retains 25 registrations and tracking states. The candidate retains zero, with
readers/controllers also zero and exact SDK unswizzling after core release.
Both candidates pass37/37; 303 affected tests pass. These weak-object measurements
are separate from RSS, allocation churn and disconnected-history accounting.
P03 remains REGRESSION BLOCKED until D08 and the original registry budget pass;
the frozen EXP-160 protocol and thresholds are unchanged. Evidence is in
[EXP-168-swiftui-lifetime.json](Results/EXP-168-swiftui-lifetime.json).


### EXP-172 registry retention repair

Signed SDK `4653e0a72` closes P03 with the original20+100+100 logical lifetimes
in Release ABBA order on27/26.5. Each of the four controls still retains220
entries in both historical registries. Every candidate collection is empty after
each boundary, with zero weak controller survivors. Candidate first100 heap
increases are512/512/832/832 bytes; second100 increases512/1,152/512/512 bytes,
within unchanged65,536/16,384 limits. The candidate fixture's single internal
constructor adaptation supplies an empty initial scene inventory; the control
already starts empty. All directly owned collections are inspected, preventing
a renamed registry from escaping the oracle.

Eight ordinary automatic/manual native runs and the watchOS Release product pass;
326 affected tests and seven oracle controls pass. Mounted host/state release
remains accepted from EXP-168/171, and H08/H09 remain physical. P01/P02/P04 are
not rerun. See [raw samples and identities](Results/EXP-172-scene-retention.json).
The protocol prefix above and original baseline workloads remain frozen.
