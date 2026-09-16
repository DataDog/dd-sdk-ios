# RUM multi-scene implementation and validation plan

This document owns ordered future work, dependencies, validation gates, and the
physical-device queue. Read the [assessment](ASSESSMENT.md) for the current
support verdict and the [experiment index](EXPERIMENTS.md) for evidence locators.
Historical planning through `EXP-142` is frozen in
[Archive/PLAN_THROUGH_EXP-142.md](Archive/PLAN_THROUGH_EXP-142.md).

Last updated: 2026-09-16

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
- a scene-scoped semantic engine is independent of any visual container and can
  accept native-adapter, optional-capability, explicit-source, coordinator, or
  automatic-discovery input;
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

## Current execution slice

### EXP-146: container-independent semantic navigation host

| Field | Contract |
| --- | --- |
| Expected outcome | The proven occurrence, transition, reveal, and authority state no longer fundamentally depends on `RUMNavigationStack`. A `RUMNavigationHost`-style boundary can wrap an arbitrary customer-owned `View` while leaving its navigation implementation unchanged. |
| Prerequisite evidence | `EXP-141`-`145` prove the current native convenience container, including sibling isolation. The revised API constraints require equivalent paths for native, custom, third-party-style, UIKit-coordinator, and automatic navigation. |
| Implementation boundary | First extract a scene-scoped, container-independent semantic engine without behavior change. Then add an iOS 27 experimental host whose content builder accepts any `View`. Keep `RUMNavigationStack` as a native convenience adapter over that engine, not the engine itself. Do not add Datadog replacements for standard presentation modifiers. |
| Current result | PARTIAL PASS. Commit `a84061840` extracts the shared engine and adds the arbitrary-content host, stable source, optional capability detection, and explicit-source precedence. Commit `354422d88` exercises unchanged standard SwiftUI through the explicit-source path. Accepted run `semantic-host-explicit-20260916-b` passes 42/42 with exact H1/D1/H2/Sheet/H3/Cover/H4 ownership and root creation before initial lifecycle work. Live capability and non-conforming fallback rows remain. |
| Acceptance | Existing `RUMNavigationStack` fixtures remain identical. A non-conforming custom container receives scene-aware automatic baseline behavior; a stable optional capability upgrades it to exact committed occurrences; an explicit source overrides capability and automatic inference. Container reconstruction retains the source, authority stays target-local, and standard `.sheet`/`.fullScreenCover` code is unchanged. |
| Environment | Focused deterministic tests and iPadOS 27 simulator. Cross-scene isolation remains a physical-device acceptance row. |

The explicit-source sub-slice is accepted with exact mapper/backend ownership, a
143/143 full probe, API-surface verification, clean lint, and an Xcode 27 Release
build. Continue `EXP-146` with the same customer-owned custom container in
capability and non-conforming modes, then measure the integration diff.

## Next ordered slices

| Order | Expected outcome | Prerequisite evidence | Implementation boundary | Acceptance test | Environment |
| ---: | --- | --- | --- | --- | --- |
| 1 | Validate optional capability against a non-conforming baseline on the same customer-owned custom container | Accepted explicit-source host | Keep the customer container and standard navigation/presentation code identical; add only a stable type-erased capability for the enhanced arm | Non-conforming content remains crash-safe and scene-aware through automatic tracking; capability arm reproduces the exact 42-event semantic oracle without per-screen changes | Simulator |
| 2 | Close native/capability/explicit adapter parity and source lifetime | Shared engine plus accepted capability path | Explicit source > capability > native adapter > automatic > representative; source stays stable across SwiftUI reconstruction and scene disconnect | Native convenience, conforming custom, and explicit third-party-style adapters produce identical H1/D1/H2 and presentation occurrences; reconstruction, cancellation, and teardown remain exact | Simulator |
| 3 | Measure customer migration and compatibility cost | Host, capability, and explicit source prototypes | Realistic multi-flow sample with standard navigation and presentations unchanged | Integration diff is isolated to SDK setup, flow boundaries, or one adapter file, not proportional to screens/presentations; no Datadog router or presentation replacement; agent-generated native SwiftUI still compiles unchanged | Simulator and source audit |
| 4 | Prototype Operation view targeting behind iOS 27 experimental boundaries | `EXP-130` identity semantics; `EXP-131` cross-scene driver; [Operations contract](OPERATIONS.md) | Opaque customer target with `.current(in:)` first; separate explicit and inferred candidates; Debug-only Objective-C companions | Start/succeed/fail calls compile and route explicit > inferred > last-proven snapshot > representative; no internal UUID leaks | Simulator for API/fallback tests; hardware for cross-scene acceptance |
| 5 | Close explicitly targeted actions, Resources, errors, view mutations, Traces, logs, WebView, and exported/fatal context | Scene-targeted view API and Operation target prototype | Existing public API overloads or scoped target seam only where source inference cannot be reliable | Each targeted signal reaches the requested scene's current view; unresolved explicit input falls through safely; legacy source-less behavior is unchanged | Simulator for one-scene/controlled rows; hardware for concurrent rows |
| 6 | Validate ordinary-app compatibility and overhead | All simulator-capable semantic fixes | Single-scene automatic/manual apps, custom handlers, event handoff, swizzle paths | No new views/actions, no custom-handler regression, bounded `sendEvent` overhead/reentrancy, all module/API/lint gates green | Simulator and benchmark host |
| 7 | Complete the physical multi-window acceptance queue below | Prepared named scenarios and clean-run recipes | No harness semantic changes unless a run exposes a proven discriminator defect | Exact mapper plus backend owner evidence on simultaneously usable scenes | iPhone Duo or physical multi-window iPad |
| 8 | Freeze the multi-scene implementation and prepare API/RFC review | Simulator and hardware blockers closed | Experimental Swift/Objective-C surfaces and documentation | Reviewed stable shape, availability/fallback story, compatibility evidence, and no unapproved API baseline changes | Review plus CI |

## Dependencies and decision gates

| Dependency or decision | Current rule |
| --- | --- |
| Public API review | Experimental iOS 27 SPI and Debug-only Objective-C prototypes may be implemented and exercised now. Stable symbols wait for normal RFC/API review. |
| Deployment compatibility | Multi-scene correctness may be iOS 27+ when an older-system solution would compromise it. The SDK must still compile and preserve existing behavior on iOS 15-26. |
| Automatic SwiftUI | Remains the zero-code default. Semantic/manual authority suppresses only its targeted scene/container and coexists with automatic tracking elsewhere. |
| Customer navigation compatibility | Do not require replacement navigation/presentation APIs, a Datadog router, or per-screen instrumentation. The integration may wrap one container or consume one existing source/adapter, but the customer's container keeps layout, behavior, gestures, animation, deep linking, and presentation. |
| Semantic precision | Exact semantics require a trustworthy accepted-route, materialization, completion/cancellation, router/coordinator, or content-boundary signal. Opaque containers fall back to scene-aware automatic tracking plus exceptional manual instrumentation; do not invent exact state. |
| Integration precedence | Explicit transition source/adapter, then optional type-erased container capability, then native convenience adapter, then scene-aware automatic discovery, then the existing process representative. Suppression remains local to the enhanced container. |
| Source-less attribution | Preserve last-interacted/process-representative behavior. Do not silently drop source-less work or require a resolver. |
| Execution Context | Preserve reliable internal scene ownership so it can map to a Window Execution Context later. Do not add a temporary wire field or split sessions. |
| Operations | Identity is application-wide `(name, operationKey)`. Duplicate starts track only the latest client start and leave the earlier backend operation to the four-hour timeout; never synthesize `auto_restart`. |
| Session Replay | Crash safety is required; multi-scene replay correctness is a follow-up. |
| Networking misuse | Do not spend this project on a developer rewriting a request from allowed to disallowed first-party capture/header status. |
| Hardware | Do not retry a topology after two equivalent simulator-system failures before the decisive signal; run the unchanged named scenario on capable hardware. |
| Open product questions | None. Public spellings remain review questions, not blockers for prototype validation. |

## Simulator-capable work

| Work | Expected outcome and prerequisite | Boundary | Acceptance |
| --- | --- | --- | --- |
| Container-independent semantic engine and explicit source | Accepted `EXP-146` sub-slice | Shared engine plus arbitrary-content outer host; no navigation or presentation replacement | Accepted 42/42 local/backend run with distinct occurrences, exact lifecycle ownership, standard SwiftUI call sites, and target-local suppression |
| Arbitrary-view host baseline | Next `EXP-146` discriminator | The same customer-owned custom container without semantic capability | Standard code remains functional, scene-aware automatic tracking stays enabled, no global suppression or crash |
| Optional capability | After/alongside baseline | Stable type-erased source detected from the supplied container; no associated route type or per-screen changes | Exact H1/D1/H2, repeated routes, commit/cancel, presentations, reconstruction, scene isolation, and precedence matching explicit/native paths |
| Migration-diff sample | After all navigation entry paths exist | Realistic 100-screen-style multi-flow sample or representative scaled fixture | Integration cost scales with containers/routers, not screens, sheets, or covers |
| Operation target API | After `EXP-130` and source review | Monitor/handler routing plus Swift/ObjC prototype | Explicit target precedence, fallback, crash safety, and source compatibility |
| Targeted downstream signals | After target abstraction exists | One signal family per slice | Exact requested owner plus legacy fallback regressions |
| Single-scene/custom-handler compatibility | After semantic state stabilizes | Existing integration paths | Full suites, representative behavior, no duplicate views/actions |
| Performance/reentrancy | After code shape freezes | `UIApplication.sendEvent` handoff and locks | Measured bounded overhead, no recursion/deadlock, normal apps unaffected |
| Missing deterministic harness controls | Before WebView, mirrored log, and fatal/exported context rows | Probe only | Named scenario, fail-closed prerequisites, mapper/backend oracle |

## Physical-device and human-driven queue

Do not close these rows with simulator prefixes or callback counts. A human
gesture closes a row only when path, coordinator, lifecycle, and RUM UUID evidence
prove the intended interaction.

| Priority | Experiments | Expected outcome | Prerequisite | Implementation boundary | Acceptance | Required environment |
| --- | --- | --- | --- | --- | --- | --- |
| P0 | `EXP-100` | SwiftUI edge-pop cancel retains Detail; completion creates fresh Home | Existing transition gate | No new implementation unless hardware disproves it | Recognized gesture plus exact path/coordinator/lifecycle/view evidence | Human, physical device |
| P0 | `EXP-081` | UIKit edge-pop cancel then completed pop matches deterministic controls | `EXP-083`/`084` | UIKit transition handling | Cancel keeps UUID; completion creates fresh returned UUID | Human, physical device |
| P0 | `EXP-086`, `EXP-103` | Both windows remain simultaneously visible and complete split navigation | Prepared two-scene split scenarios | Scene/view ownership only | Both A/B chains finish with distinct IDs and exact owners | iPhone Duo or physical iPad |
| P0 | `EXP-041`, `EXP-089`, `EXP-113` | B is representative while visible A work remains A-owned; closing B does not disturb A | Exact scene registry and close driver | Action/view/lifecycle ownership | A action/Resource and post-close continuity retain A ID | Simultaneously usable windows |
| P0 | `EXP-114` | Real focus/activation handoff backgrounds the peer | Latched lifecycle driver | Probe unless SDK behavior fails | Target foreground-active, peer background, exact owner evidence | iPhone Duo or physical iPad |
| P0 | `EXP-118` | Semantic A coexists with automatic B | Target-scoped authority | Automatic predicate plus semantic SPI | B automatic view starts after B opens; neither scene suppresses or owns the other | Simultaneously usable windows |
| P0 | `EXP-129` | Same manual key exists independently in A/B and stops in reverse order | Scene-targeted manual API | Manual stack authority | Distinct Compose UUIDs; B stop never preempts A; fresh Home per scene | iPhone Duo or physical iPad |
| P0 | `EXP-131` | Operations start in A and finish in B; parallel keys finish B-before-A | Operation step model and target prototype when available | Raw steps and reducer | Eight raw steps and four reduced Operations with exact start/end views | iPhone Duo or physical iPad |
| P0 | `EXP-136` | One A-created request joined from B remains one A-owned Trace | Existing held request driver | Trace request-start ownership | Exactly one A/Home span, zero B owner and zero duplicate | Physical multi-window device |
| P1 | `EXP-076`, `EXP-087` | Regular → compact → regular keeps the one-current-destination contract | Acknowledged resize control | SwiftUI/UIKit split handling | Exact geometry/selection/path/view sequence with no structural view | Resizable capable device |
| P1 | `EXP-042` | A and B restore concurrently with fresh RUM occurrences | Restoration controls from `EXP-143` | Scene lifecycle/restoration | Both native scene sessions reconnect; no stale RUM scope or cross-owner work | Physical multi-window device |
| P1 | `EXP-001` | UIKit-hosted SwiftUI parity, only if still a release requirement | Final host matrix decision | Example/probe host | Same semantic and attribution guarantees as native host | Physical device |

Forward-looking hardware gates without dedicated IDs remain: genuine
disconnect/reconnect, isolated per-scene background/foreground, and the final
iPhone Duo iOS 27.1 release matrix. `EXP-039` is not in this queue because its
candidate was never constructed; it needs a deterministic harness instead.

## Release and compatibility gates

The branch is not release-ready until all applicable gates pass:

- View lifecycle: opening, navigating, hiding, restoring, and closing one scene
  never replaces another scene's current branch; navigation returns use fresh IDs.
- SwiftUI: zero-code limitations are documented; the reviewed host/adapter model
  preserves native and existing navigation code, keeps integration cost bounded
  by containers/routers, and handles stack, presentation, repeated routes,
  router mutation, restoration, coexistence, and cancellation without duplicates.
- UIKit: push/pop/modal/split behavior passes automatic, subclass, interactive,
  adaptive, and concurrent-window cases.
- Manual views: exact scene/key pairing, nesting, underlying navigation, duplicate
  misuse crash safety, same-key A/B isolation, and legacy source-less compatibility.
- Attribution: actions, Resources, errors, mutations, Traces, logs, WebView,
  Operations, fatal/exported context, long tasks, and vitals have evidence at the
  appropriate source/mapper/backend tier.
- Lifecycle: activation, per-scene foreground/background, disconnect/reconnect,
  restoration, session rollover, and originating-scene closure are covered.
- Compatibility: full affected module suites, package builds, lint, API surface,
  Objective-C smoke, custom/NOP conformers, single-scene runtime, and supported
  deployment targets pass.
- Performance and safety: measured event-handoff overhead is acceptable, locking
  is reentrant-safe, no SDK-caused crash, and Session Replay remains crash-safe.
- Hardware: the P0 queue and final iPhone Duo/iOS 27.1 matrix pass unchanged named
  scenarios with exact backend evidence.

Latest checkpoint: accepted `EXP-146` run
`semantic-host-explicit-20260916-b` passes 42/42 locally and exact backend intake
on host commit `a84061840` and probe/oracle commit `354422d88`. Its session has
exactly eight views including launch, 26 actions, 26 Resources, zero
errors/crashes, no automatic duplicate, and no downstream work on
ApplicationLaunch. The native probe passes 143/143, repository lint is clean
across 713 source and 699 test files, API-surface verification passes, and the
Xcode 27.0 Release probe build passes. Complete DatadogRUM passes 1,262/1,263;
the sole unrelated timeseries timing failure passed immediately in isolation.
DatadogTrace remains 151/151 at its latest affected checkpoint.
Unaffected module suites remain valid at their recorded checkpoints but must
rerun at the release freeze.

## Completed milestone ledger

| Milestone | Experiments | Result | Detailed history |
| --- | --- | --- | --- |
| Released-baseline assessment and core scene model | `EXP-001`-`020` | Per-scene view branches, downstream owner snapshots, teardown, and Operations feasibility established; baseline early-source gaps retained | [Experiment archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md), [plan archive](Archive/PLAN_THROUGH_EXP-142.md) |
| Automatic SwiftUI diagnosis and early explicit boundary | `EXP-021`-`065` | Automatic discovery proved semantically late; iOS 27 route-owned occurrence state, cancellation, reconnect fencing, and customer-state-preserving identity established | Same archives |
| SwiftUI/UIKit split and causal ownership | `EXP-066`-`105` | Semantic split occurrences, UIKit structural-column handling, exact action/Resource/error/mutation/Trace routing, and retained returns established; hardware gaps isolated | Same archives |
| Deterministic probe and lifecycle driver | `EXP-106`-`114` | Named scenarios, JSONL recorder, reducer/oracle, exact scene registry, signal-driven stack/split/UIKit/lifecycle flows, and hardware routing established | Same archives |
| Automatic coexistence and manual authority | `EXP-115`-`129`, `EXP-137`-`140` | Target-local authority, underlying navigation, nesting, Sheet/cover, sibling isolation, and customer-shaped scene-targeted manual SPI pass; same-key A/B remains hardware-gated | Same archives |
| Operations, scroll, Trace, and causal boundary | `EXP-130`-`136` | Navigation-step Operations, real scroll origin, Trace request-start freezing, reverse completion, and approved source-less SwiftUI task fallback classified; cross-scene/shared rows prepared | Same archives |
| Native-convenience semantic navigation proof | `EXP-141`-`145` | Complete stack/presentation SPI, repeated equal values, restoration, external replacement/rejection/canonicalization, bidirectional presentation replacement, and actual-SPI sibling isolation pass locally and in backend intake; latest probe/oracle `144d6e0e7` | Same archives plus [active EXP-143-145 records](Experiments/EXP-143-199.md) |

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
- The canonical overview now measures 1,047 lines, 10,299 words, and 77,848
  bytes after the necessary routing/current-checkpoint corrections. Schedule a
  separate deduplication pass; do not mix it into this lossless hot-document
  compaction.

## Evidence routing

- Current support: [ASSESSMENT.md](ASSESSMENT.md)
- Experiment lookup: [EXPERIMENTS.md](EXPERIMENTS.md)
- New detailed records: [Experiments/EXP-143-199.md](Experiments/EXP-143-199.md)
- Rejected paths: [REJECTED_APPROACHES.md](REJECTED_APPROACHES.md)
- Tool workflow: [TOOLING_RUNBOOK.md](TOOLING_RUNBOOK.md)
- Frozen plan: [Archive/PLAN_THROUGH_EXP-142.md](Archive/PLAN_THROUGH_EXP-142.md)
