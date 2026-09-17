# RUM multi-scene release checklist

Last updated: 2026-09-17. This file owns the finite remaining release contract.
[release-gates.json](release-gates.json) is the machine-readable register.
Progress is gates closed, not experiment count. Completed planning narratives
were moved to [completed notes](Experiments/PLAN_COMPLETED_THROUGH_EXP-159.md);
attempt details remain in the experiment ledger.

## Current objective and scope

Deliver correct RUM attribution for concurrent iPad and iPhone windows, with
iPhone Duo on iOS 27.1 as the release target. The branch must preserve ordinary
single-scene behavior and the iOS 15 deployment target.

The approved model is:

- one current RUM destination per scene;
- RUM views represent navigation-path occurrences, not platform object identity;
- returning to the same destination creates a fresh view ID;
- automatic tracking remains the zero-code default;
- exact SwiftUI navigation is an optional once-per-container or once-per-router
  enhancement around the application's existing navigation system; standard
  `NavigationStack`, `.sheet`, `.fullScreenCover`, and custom-container call
  sites must not be replaced throughout the screen hierarchy;
- semantic correctness must not require per-destination metadata, an exhaustive
  RUM-only route/presentation resolver, or RUM calls in every navigation method;
  default metadata is automatic and customer overrides are sparse;
- a scene-scoped semantic engine is independent of any visual container and can
  accept native-adapter, optional-capability, explicit-source, coordinator, or
  automatic-discovery input;
- the explicit transition source is an engine and adapter-author primitive, not
  the representative normal-app integration;
- exact manual authority is scene-targeted, nestable by distinct key, and paired
  with an exact targeted stop;
- source-less work keeps the last-interacted/process-representative fallback;
- Operations remain application-wide by `(name, operationKey)` and resolve every
  step's view independently;
- scene ownership must be ready to map to a future Window Execution Context, but
  this work introduces no temporary attribute, session split, or wire format; and
- Session Replay only needs to remain crash-safe.

No product question blocks the next internal experiment. Stable API names and
Objective-C Release exposure still require normal API review.

## Execution and experiment admission

0. D01/D02 platform compatibility is closed by EXP-162; evidence is in the
   register and detailed record. Accepted experiment identities remain unchanged.
1. Execute predefined EXP-163 for D12 overdue-stop metadata, the smallest
   deterministic slice in the independent D09/D11/D12 compatibility group. Then
   repair D09/D11 in the [assessed order](REVIEW_TRIAGE.md). Define each bounded
   experiment before implementation; preserve failing controls.
2. Repair D04 together with P02 allocation cost; normalize restoration in D05/D06.
3. Repair D03/P03 lifetimes, D07/D08 authority/reconnect, and D10 accepted
   presentation state. Close the missing R04–R06 discriminators in those slices.
4. Close the early compatibility/performance gates in available environments;
   C06 remains blocked without a minimum-OS runtime. Resume T03–T14 only after
   relevant repair dependencies pass. A documented fallback remains a deliverable.
5. Resume hardware at H01 when capable iPad/Duo hardware is available, respecting
   H08/H09/H13 repair dependencies. Finish API/docs/CI, final Duo acceptance and
   release freeze. Deferred extraction remains after freeze.

A new EXP record must name one or more existing gate IDs, a frozen candidate,
predeclared decisive oracle and environment, and which result closes each gate.
It may instead investigate a concrete regression with a reproduction. New scope
requires an explicit checklist change with rationale; it cannot enter as an
unnamed “remaining signal.” A failed or inconclusive attempt does not create
another deliverable. Do not repeat accepted experiments merely to resume.

Owners below are responsible roles: the current implementer owns SDK/harness
work; reviewers own sign-off; the device operator owns physical/human evidence.
No external reviewer sign-off is implied. `CLOSED` is bounded by cited evidence;
`ENVIRONMENT BLOCKED` is still a required gate. EXP-039's unbuilt automatic
reflection candidate is not admitted: opaque/automatic limits are the approved
fallback covered by F02, not an exact-navigation release claim. UIKit-hosted
SwiftUI remains required as H16; the former conditional row is resolved.

## Compatibility

| Gate | Deliverable / completion mode | Owner | Depends on | Decisive test | Environment | Status |
| --- | --- | --- | --- | --- | --- | --- |
| C01 | Ordinary single-scene automatic app | SDK implementer | None | Unchanged Home → Detail → fresh Home owner/name/count chain, no duplicate views/actions | iOS 27 and 26.5 simulators | CLOSED |
| C02 | Ordinary single-scene manual app | SDK implementer | None | Exact manual start/stop and marker owners match the pinned baseline | iOS 27 and 26.5 simulators | CLOSED |
| C03 | Legacy UIApplication lifecycle app | SDK implementer | None | No scene manifest; automatic and manual chains match baseline without a scene registry dependency | iOS 27 and 26.5 simulators | INCONCLUSIVE |
| C04 | Custom and NOP monitor compatibility | SDK implementer | None | Legacy-only conformer receives exactly one call; NOP emits nothing and never crashes | iOS 27 and 26.5 simulators | CLOSED |
| C05 | Older supported runtime sample | SDK implementer | None | Repeat C01–C04 on iOS 26.5 with no new experimental availability requirement | iOS 27 and 26.5 simulators | CLOSED |
| C06 | Minimum-supported runtime | SDK implementer | None | Repeat automatic/manual/legacy smoke on iOS 15; compile minimum deployment target independently | iOS 15 device/runtime | ENVIRONMENT BLOCKED |

## Performance and reentrancy

| Gate | Deliverable / completion mode | Owner | Depends on | Decisive test | Environment | Status |
| --- | --- | --- | --- | --- | --- | --- |
| P01 | Event-dispatch overhead | SDK implementer | C01 | Release ABBA comparison passes predeclared median/p95 thresholds in BASELINES.md | Same simulator/toolchain, Release build; focused internal lifecycle tests | CLOSED |
| P02 | Allocation cost | SDK implementer | C01, D04 | Measured allocation count and bytes per fixed workload pass baseline deltas; net heap is not allocation churn | Same simulator/toolchain, Release build; focused internal lifecycle tests | REGRESSION BLOCKED |
| P03 | Retained scene state | SDK implementer | C01, D03, D08 | Repeated create/disconnect/release leaves no SDK-owned scene/controller/host and no growing registry | Same simulator/toolchain, Release build; focused internal lifecycle tests | REGRESSION BLOCKED |
| P04 | Reentrancy | SDK implementer | C01 | Nested A→B→A dispatch restores exact outer context; one original call each, no deadlock or leaked task/thread context | Same simulator/toolchain, Release build; focused internal lifecycle tests | CLOSED |

## Incremental responsibility review

| Gate | Deliverable / completion mode | Owner | Depends on | Decisive test | Environment | Status |
| --- | --- | --- | --- | --- | --- | --- |
| R01 | Trait readers and tracking lifetimes | SDK reviewer | None | Reader identity, migration, remount, weak ownership and disconnect fencing; record findings, evidence and dispositions in COMPONENT_REVIEW.md | Source review plus targeted regressions for any finding | CLOSED |
| R02 | Authority and occurrence sources | SDK reviewer | D03 | Exact host release, local suppression, stale generation rejection and fresh reveals; record findings, evidence and dispositions in COMPONENT_REVIEW.md | Source review plus targeted regressions for any finding | REVIEW BLOCKED |
| R03 | Transition arbitration | SDK reviewer | None | Accepted versus proposed state; cancel/finish exactly once; nested reentrancy; record findings, evidence and dispositions in COMPONENT_REVIEW.md | Source review plus targeted regressions for any finding | CLOSED |
| R04 | View modifiers and attachment boundaries | SDK reviewer | D03, D08 | Main-thread/availability gates, host reconstruction and retained-reader teardown; record findings, evidence and dispositions in COMPONENT_REVIEW.md | Source review plus targeted regressions for any finding | REVIEW BLOCKED |
| R05 | Observed input and semantic engine | SDK reviewer | D07, D08 | Publisher pinning, Observation rearming, background FIFO and atomic destination; record findings, evidence and dispositions in COMPONENT_REVIEW.md; multiple observers with nested commit/remove/add must preserve monotonic generations | Source review plus targeted regressions for any finding | REVIEW BLOCKED |
| R06 | Public hosts and native convenience adapters | SDK reviewer | D10 | Migration budget, no screen/method edits, automatic metadata and platform fallback; record findings, evidence and dispositions in COMPONENT_REVIEW.md; delayed detach/remount and same-ID presentation replacement preserve occurrence ownership | Source review plus targeted regressions for any finding | REVIEW BLOCKED |

## Acceptance workflow

| Gate | Deliverable / completion mode | Owner | Depends on | Decisive test | Environment | Status |
| --- | --- | --- | --- | --- | --- | --- |
| A01 | Repeatable acceptance workflow | Harness implementer | None | One invocation performs preflight → clean install → frozen build → scenario → topology → strict semantics → backend; negative controls fail closed and durable summary is produced | Simulator + authenticated Datadog connector; physical/human capabilities remain explicit | CLOSED |

## Telemetry completion contracts

| Gate | Deliverable / completion mode | Owner | Depends on | Decisive test | Environment | Status |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | One-shot actions — explicit target | SDK implementer | C04 | EXP-158 exact A/B owner and unresolved-target/custom/NOP fallback | iOS 27 simulator, focused compatibility tests, exact mapper and Datadog backend owners | CLOSED |
| T02 | Long-running actions — explicit target | SDK implementer | C04, D12 | EXP-159 B-before-A, empty B stop isolation, exact final metadata; navigation/timeout retain original owner | iOS 27 simulator, focused compatibility tests, exact mapper and Datadog backend owners | REVIEW BLOCKED |
| T03 | Manual and automatic Resources — explicit start target + captured start ownership | SDK implementer | A01, D01, D04, D05, D06 | Target A start while B represents; success/error/metrics after navigation/teardown remain A-owned; duplicate-key behavior documented; late failed completion cannot increment another session's live continuous action | iOS 27 simulator, URLSession/manual Resource fixture, mapper and Datadog backend | OPEN |
| T04 | Current-view errors — explicit target | SDK implementer | A01 | Requested live view owns message/Error/completion-handler forms; invalid target falls back; Resource errors retain T03 owner | iOS 27 simulator, focused compatibility tests, exact mapper and Datadog backend owners | OPEN |
| T05 | View attributes and removal — explicit target | SDK implementer | A01 | Single/batch add/remove changes only requested current view; global monitor attributes remain process-wide | iOS 27 simulator, focused compatibility tests, exact mapper and Datadog backend owners | OPEN |
| T06 | Custom timing and loading time — explicit target | SDK implementer | A01 | Requested occurrence receives timing/loading mutation with existing overwrite rules and no peer mutation | iOS 27 simulator, focused compatibility tests, exact mapper and Datadog backend owners | OPEN |
| T07 | Feature flags and internal view mutations — explicit target where customer-callable; captured call-site ownership internally | SDK implementer | A01 | Flags and internal performance/cross-platform attributes preserve same-scene stale-view fallback; no public API for internal-only fields | iOS 27 simulator, focused compatibility tests, exact mapper and Datadog backend owners | OPEN |
| T08 | Manual/automatic/OpenTelemetry Traces — captured start ownership | SDK implementer | A01, D04 | Native/OTel/URLSession start in A then complete under B; one span, A context, no retarget or duplicate; source-less starts document representative fallback | iOS 27 simulator, Trace/OTel/URLSession fixtures and backend; shared request also H07 | OPEN |
| T09 | Logs and mirrored errors — captured emission ownership | SDK implementer | A01, D04 | A-origin log and mirrored RUM error agree on captured view/action despite B representative churn; source-less log uses documented representative | iOS 27 simulator, Logs/RUM mirror fixture and Datadog backend | OPEN |
| T10 | WebView bridge — captured native-container ownership | SDK implementer | A01, D02, D11 | Two actual web containers retain their bound native view owners; navigation/rebind/teardown cannot inherit the peer | Two native WebView containers on iOS simulator plus backend; macOS compile in D02 | OPEN |
| T11 | Exported and fatal/crash context — documented process-level fallback; trustworthy internal snapshot remains exact | SDK implementer | A01 | Source-less export/fatal signal appears once on representative; explicit internal snapshot does not drift; no fabricated scene ownership | Deterministic crash/export context tests and isolated simulator process/backend | OPEN |
| T12 | Long tasks, app hangs and memory warnings — documented process-level fallback | SDK implementer | A01 | One process signal appears once on representative; no per-scene broadcast or invented causal owner | Controlled long-task/hang/memory-warning tests and simulator backend | OPEN |
| T13 | Vitals — documented process-level measurement with existing view association | SDK implementer | A01 | CPU/memory/frame metrics retain documented process sampling and view association; never claim independent per-window measurement | Fixed process metric fixture, view associations and backend; representative device sample before freeze | OPEN |
| T14 | Profiling — documented process-level fallback | SDK implementer | A01 | Process profile and exact Operation identity remain correlated; docs make no per-scene CPU attribution claim | Profiling/Operation fixture and supported profiling device/backend | OPEN |
| T15 | Operations — explicit per-step target or captured call-site ownership; last-proven then process fallback | SDK implementer | C04 | Application-wide name/key identity, A→B start/end and reverse parallel completion; duplicate starts leave older backend timeout | iOS 27 simulator, focused compatibility tests, exact mapper and Datadog backend owners | CLOSED |

## Physical-device and human-driven queue

| Gate | Deliverable / completion mode | Owner | Depends on | Decisive test | Environment | Status |
| --- | --- | --- | --- | --- | --- | --- |
| H01 | Same-key manual A/B reverse stop | Device operator + SDK implementer | A01 | EXP-129: distinct Compose IDs, B stop preserves A, fresh Home per scene | Physical iPad/iPhone Duo; human gesture for H11–H13; resize-capable for H14 | ENVIRONMENT BLOCKED |
| H02 | Concurrent UIKit and SwiftUI split navigation | Device operator + SDK implementer | A01 | EXP-086/103: simultaneously visible A/B chains, distinct occurrences, no structural view | Physical iPad/iPhone Duo; human gesture for H11–H13; resize-capable for H14 | ENVIRONMENT BLOCKED |
| H03 | Visible peer attribution and close continuity | Device operator + SDK implementer | A01 | EXP-041/089/113: A work stays on A while B represents; B close never stops A | Physical iPad/iPhone Duo; human gesture for H11–H13; resize-capable for H14 | ENVIRONMENT BLOCKED |
| H04 | Actual focus and activation | Device operator + SDK implementer | A01 | EXP-114: target foreground-active, peer background, exact lifecycle and event owners | Physical iPad/iPhone Duo; human gesture for H11–H13; resize-capable for H14 | ENVIRONMENT BLOCKED |
| H05 | Semantic/automatic coexistence across scenes | Device operator + SDK implementer | A01 | EXP-118: semantic A and automatic B neither suppress nor own each other | Physical iPad/iPhone Duo; human gesture for H11–H13; resize-capable for H14 | ENVIRONMENT BLOCKED |
| H06 | Concurrent inferred Operations topology | Device operator + SDK implementer | A01 | EXP-131/157 accepted ownership repeated with simultaneous visible topology evidence | Physical iPad/iPhone Duo; human gesture for H11–H13; resize-capable for H14 | ENVIRONMENT BLOCKED |
| H07 | Shared URLSession request | Device operator + SDK implementer | A01 | EXP-136: A-created request joined in B yields exactly one A span and no RUM Resource in trace-only mode | Physical iPad/iPhone Duo; human gesture for H11–H13; resize-capable for H14 | ENVIRONMENT BLOCKED |
| H08 | Final semantic host removal | Device operator + SDK implementer | A01, D03, D07 | EXP-146: real final A removal stops A once, releases source, preserves B and rejects resurrection | Physical iPad/iPhone Duo; human gesture for H11–H13; resize-capable for H14 | ENVIRONMENT BLOCKED |
| H09 | Genuine disconnect, reconnect and remount | Device operator + SDK implementer | A01, D03, D08, P03 | OS-driven disconnect/remount, no posted substitutes; fresh occurrence, stale callbacks fenced, peer continuity | Physical iPad/iPhone Duo; human gesture for H11–H13; resize-capable for H14 | ENVIRONMENT BLOCKED |
| H10 | Isolated per-scene background/foreground | Device operator + SDK implementer | A01 | Background A while B remains usable; neither lifecycle transition replaces peer current view | Physical iPad/iPhone Duo; human gesture for H11–H13; resize-capable for H14 | ENVIRONMENT BLOCKED |
| H11 | UIKit interactive edge pop | Device operator + SDK implementer | A01 | EXP-081: recognized cancel preserves Detail ID; recognized completion reveals fresh Home | Physical iPad/iPhone Duo; human gesture for H11–H13; resize-capable for H14 | ENVIRONMENT BLOCKED |
| H12 | SwiftUI interactive edge pop | Device operator + SDK implementer | A01 | EXP-100: recognized cancel preserves Detail ID; completion commits fresh Home before work | Physical iPad/iPhone Duo; human gesture for H11–H13; resize-capable for H14 | ENVIRONMENT BLOCKED |
| H13 | Interactive presentation dismissal | Device operator + SDK implementer | A01, D10 | EXP-152: cancelled Sheet retains ID; completed dismissal yields one fresh Home before actual callback work | Physical iPad/iPhone Duo; human gesture for H11–H13; resize-capable for H14 | ENVIRONMENT BLOCKED |
| H14 | Adaptive split resize | Device operator + SDK implementer | A01 | EXP-076/087: measured regular → compact → regular geometry, selection, path and exact owners | Physical iPad/iPhone Duo; human gesture for H11–H13; resize-capable for H14 | ENVIRONMENT BLOCKED |
| H15 | Concurrent scene restoration | Device operator + SDK implementer | A01 | EXP-042: both native sessions reconnect with fresh RUM IDs and no stale run attributes | Physical iPad/iPhone Duo; human gesture for H11–H13; resize-capable for H14 | ENVIRONMENT BLOCKED |
| H16 | UIKit-hosted SwiftUI parity | Device operator + SDK implementer | A01 | EXP-001 follow-up: same semantic/lifecycle/ownership contract in UIHostingController as WindowGroup | Physical iPad/iPhone Duo; human gesture for H11–H13; resize-capable for H14 | ENVIRONMENT BLOCKED |

## Reported regression repair gates

A concurrent production safety review introduced these finite obligations on
2026-09-17. [REVIEW_TRIAGE.md](REVIEW_TRIAGE.md) assesses all 12 findings and repair timing.
Source-traced or extracted-probe findings still need their stated regression tests; a gate closes after repair or evidence-backed rejection.
SwiftUI findings are also triaged in COMPONENT_REVIEW.md. Existing accepted
experiment slices remain evidence, not a substitute for these missing cases.

| Gate | Deliverable / completion mode | Owner | Depends on | Decisive test | Environment | Status |
| --- | --- | --- | --- | --- | --- | --- |
| D01 | watchOS Resource compile compatibility | SDK implementer | None | Reproduce/triage the reported finding, then require: DatadogRUM watchOS build including absent UI handoff | watchOS SDK build | CLOSED |
| D02 | macOS WebView compile compatibility | SDK implementer | None | Reproduce/triage the reported finding, then require: DatadogWebViewTracking macOS build with absent UIKit scene metadata | macOS SDK build | CLOSED |
| D03 | Keyed SwiftUI registration teardown | SDK implementer | None | Reproduce/triage the reported finding, then require: Mounted keyed destination removal plus SDK release: weak registration/instrumentation release and balanced unswizzling; repeat cycles | iOS 27 simulator, mounted SwiftUI host and lifetime checks | REGRESSION BLOCKED |
| D04 | Named-core handoff isolation | SDK implementer | None | Reproduce/triage the reported finding, then require: Different cores, same application/different sessions, no-RUM core, nested dispatch and inherited work after stop/reinitialize never consume foreign context | Internal, RUM, Logs, Trace and network focused tests | REGRESSION BLOCKED |
| D05 | Resolve ownership before explicit session restart | SDK implementer | None | Reproduce/triage the reported finding, then require: After stopSession with A/B and B representative, source-less start replaces B and preserves A; identity-stop A preserves B | RUM application/session tests plus two-scene simulator | REGRESSION BLOCKED |
| D06 | Preserve peers on lazy session expiration | SDK implementer | D05 | Reproduce/triage the reported finding, then require: Expiring lifecycle command followed by start/stop in A restores eligible B with fresh new-session ownership | RUM application/session tests plus two-scene simulator | REGRESSION BLOCKED |
| D07 | Pending semantic authority | SDK implementer | D03 | Reproduce/triage the reported finding, then require: Empty explicit/capability source and absent instrumentation do not suppress automatic tracking; first accepted snapshot acquires local authority | iOS 27 simulator with real authority registry | REGRESSION BLOCKED |
| D08 | Reconnect generation acceptance | SDK implementer | D03, D07 | Reproduce/triage the reported finding, then require: Stale trait between disconnect and real connection/reader mount cannot consume generation; exactly one fresh occurrence and correct immediate telemetry | Deterministic iOS 27 regression; genuine lifecycle remains H09 | REGRESSION BLOCKED |
| D09 | Controller API caller-thread compatibility | SDK implementer | None | Reproduce/triage the reported finding, then require: Background start/stop getter spy records no UIKit hierarchy access; main-thread target resolves correctly without sync-to-main deadlock | iOS simulator focused test plus Main Thread Checker | REGRESSION BLOCKED |
| D10 | Accepted presentation state | SDK implementer | None | Reproduce/triage the reported finding, then require: Rejected/canonicalized Binding writes, transaction forwarding, immediate setter work and dismissal callbacks follow accepted occurrence | Mounted iOS 27 SwiftUI adapter tests | REGRESSION BLOCKED |
| D11 | Legacy native/WebView correlation | SDK implementer | None | Reproduce/triage the reported finding, then require: Legacy string-key view plus mounted WKWebView retains unambiguous container.view.id; peer scene never used as fallback | Single-scene simulator WebView with Replay correlation enabled | REGRESSION BLOCKED |
| D12 | Expired action stop attributes | SDK implementer | None | Reproduce/triage the reported finding, then require: Single-scene continuous action stopped after timeout retains original stop attributes; peer timeout still cannot inherit foreign attributes | RUM scope regression with controlled clock | REGRESSION BLOCKED |

## Release and compatibility gates

| Gate | Deliverable / completion mode | Owner | Depends on | Decisive test | Environment | Status |
| --- | --- | --- | --- | --- | --- | --- |
| F01 | Stable API review | RUM API reviewers | T03, T04, T05, T06, T07, R06 | Reviewed RFC resolves Swift/ObjC names, availability, target forms, custom-conformer behavior and migration; only then update API baselines | API review | OPEN |
| F02 | Support documentation | SDK implementer | F01 | Each telemetry family documents its exact completion mode and automatic/opaque limits; feature docs match source | Source/doc review | OPEN |
| F03 | Final compatibility build/test matrix | SDK implementer | F01, D01, D02, D09, D11, D12 | All affected modules, ObjC Release, SPM iOS/macOS/tvOS/watchOS/visionOS, lint and approved API baselines pass at frozen revision | CI + supported SDK toolchains | OPEN |
| F04 | iPhone Duo release acceptance | Device operator | H01, H02, H03, H04, H05, H06, H07, H08, H09, H10, H11, H12, H13, H14, H15, H16 | Run the finite accepted scenario matrix on iPhone Duo iOS 27.1; exact mapper/backend owners and no SDK crash | iPhone Duo iOS 27.1 | OPEN |
| F05 | Session Replay coexistence | SDK implementer | A01 | Enable Replay through two scenes, navigation and teardown without SDK-caused crash; no scene-correct replay claim | Physical multi-window device | OPEN |
| F06 | Release freeze | RUM maintainers | All preceding gates | Every required gate closed on reviewed source; performance thresholds hold; no unresolved correctness/release-review finding | Review + CI | OPEN |

## Dependencies and decision gates

| Dependency or decision | Current rule |
| --- | --- |
| Public API review | Experimental iOS 27 SPI and Debug-only Objective-C prototypes may be implemented and exercised now. Stable symbols wait for normal RFC/API review. |
| Deployment compatibility | Multi-scene correctness may be iOS 27+ when an older-system solution would compromise it. The SDK must still compile and preserve existing behavior on iOS 15-26. |
| Automatic SwiftUI | Remains the zero-code default. Semantic/manual authority suppresses only its targeted scene/container and coexists with automatic tracking elsewhere. |
| Customer navigation compatibility | Do not require replacement navigation/presentation APIs, a Datadog router, per-screen instrumentation, exhaustive RUM-only metadata switches, or `willNavigate`/`commit` calls in every router method. EXP-147 proves one integration per existing observable router/container, automatic metadata, sparse overrides, and route/presentation-growth independence; every SDK-owned candidate must preserve that budget. |
| Semantic precision | Exact semantics require a trustworthy accepted-route, materialization, completion/cancellation, router/coordinator, or content-boundary signal. Opaque containers fall back to scene-aware automatic tracking plus exceptional manual instrumentation; do not invent exact state. |
| Engine input precedence | Explicit adapter source, then optional type-erased container capability, then native adapter, then scene-aware automatic discovery, then the existing process representative. This is engine behavior, not a recommendation that normal applications manually publish every transition. Suppression remains local to the enhanced container. |
| Source-less attribution | Preserve last-interacted/process-representative behavior. Do not silently drop source-less work or require a resolver. |
| Execution Context | Preserve reliable internal scene ownership so it can map to a Window Execution Context later. Do not add a temporary wire field or split sessions. |
| Operations | Identity is application-wide `(name, operationKey)`. Duplicate starts track only the latest client start and leave the earlier backend operation to the four-hour timeout; never synthesize `auto_restart`. |
| Session Replay | Crash safety is required; multi-scene replay correctness is a follow-up. |
| Networking misuse | Do not spend this project on a developer rewriting a request from allowed to disallowed first-party capture/header status. |
| Hardware | Do not retry a topology after two equivalent simulator-system failures before the decisive signal; run the unchanged named scenario on capable hardware. |
| Open product questions | None. Public spellings remain review questions, not blockers for prototype validation. |

## Deferred and explicitly out of scope

- [Deferred single-scene extraction](DEFERRED_SINGLE_SCENE_EXTRACTION.md) starts
  only after the multi-scene freeze gate.
- Simultaneous multi-pane/tab destinations need a broader RUM model; this project
  deliberately keeps one current destination per scene.
- Window Execution Context serialization and backend visualization are separate
  work. This branch preserves the internal ownership seam only.
- Full Session Replay multi-scene correctness is out of scope; crash safety is in.
- iOS 15/16 semantic multi-scene behavior is not required if it compromises the
  iOS 27+ solution.
- Rewritten-request header/capture misuse is a developer error and is not a
  robustness target for this project.
- Profiling remains process-level; document that boundary rather than inventing
  per-scene semantics.
- Stable public API names, overload breadth, and Objective-C Release exposure are
  review outcomes. Do not expose internal RUM UUIDs or add view handles now.

## Evidence routing

- [Assessment](ASSESSMENT.md), [experiment index](EXPERIMENTS.md),
  [current experiment records](Experiments/EXP-143-199.md).
- [Baseline protocol](BASELINES.md), [component review](COMPONENT_REVIEW.md),
  [production-review triage and repair order](REVIEW_TRIAGE.md),
  [tooling runbook](TOOLING_RUNBOOK.md).
- Completed experiment prose is outside this plan. Do not load the frozen
  pre-EXP-143 archive unless investigating a specific older experiment.
