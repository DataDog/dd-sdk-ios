# RUM multi-scene support assessment

This document owns the current support verdict and remaining product gaps. Use
[PLAN.md](PLAN.md) for ordered work and hardware routing, and
[EXPERIMENTS.md](EXPERIMENTS.md) for exact evidence locators. The complete
assessment through `EXP-142` is frozen in
[Archive/ASSESSMENT_THROUGH_EXP-142.md](Archive/ASSESSMENT_THROUGH_EXP-142.md).

Last updated: 2026-09-16

## Current verdict

The released SDK baseline is not semantically safe for applications with
concurrent scenes. Process-representative view state and process-global SwiftUI
controller discovery can make one window replace or own telemetry from another,
especially during early scene creation and automatic SwiftUI navigation.

This branch has a credible iOS 27 multi-scene model, but it is not release-ready.
It keeps independent scene view branches, one current destination per scene, and
fresh RUM occurrences for committed navigation. UIKit, explicit SwiftUI,
scene-targeted manual authority, Operations across navigation, actions,
Resources, and Traces have substantial mapper/backend evidence. The experimental
manual-view APIs are useful and pass their one-scene scenarios. The SwiftUI
transition source and host prove the engine and adapter boundary. The SDK-owned
publisher and one-shot Observation router paths pass their low-cost migration
and runtime gates. EXP-150 proves that a plain current-destination value read
during SwiftUI reconstruction is too late; EXP-151 proves that an existing iOS
27 `@Observable` router can instead deliver the accepted destination before its
setter returns and preserve exact post-dismiss attribution. EXP-152 confirms
that SwiftUI's actual Sheet and full-screen-cover `onDismiss` callbacks then run
against those fresh revealed occurrences and do not create another Home.

The remaining risk is concentrated in automatic SwiftUI limitations, selecting
which trustworthy low-cost adapters qualify for promotion, completing genuine
scene disconnect/remount and final-host-removal runtime evidence, simultaneously
usable window hardware, explicit
target APIs for work without reliable source context, downstream-surface runtime
coverage, lifecycle/restoration, API review, and ordinary-app
compatibility/performance.
No product decision blocks the next internal experiment.

## Support matrix

| SDK surface | Current branch support | Strongest evidence | Confirmed gap or remaining gate |
| --- | --- | --- | --- |
| View creation and lifecycle | Independent UIKit and explicitly tracked SwiftUI scene branches coexist in one RUM session. Navigation creates occurrences rather than reusing platform identity. One scene teardown does not resurrect or stop another branch. | Two-window backend runs beginning with `EXP-002`; occurrence/reconnect state tests `EXP-060`-`066`; signal-driven chains `EXP-109`-`113` | Released baseline remains process-representative. Simultaneous visibility, activation, peer close, reconnect, and two-scene restoration still need capable hardware. |
| SwiftUI navigation | The iOS 27 semantic engine is independent of a visual container. The native convenience SPI and arbitrary-content host prove committed fresh occurrences, unchanged standard `NavigationStack`/sheet/cover rendering, target-local authority, exact input precedence, and stable source lifetime. Opaque content retains automatic capture without guessed semantic views. EXP-148 adds an SDK-owned accepted-state publisher observer with automatic metadata, sparse overrides, equal-route occurrence identity, delayed authority, and route-count-independent integration. EXP-149 closes actual host reconstruction/subscription pinning, publisher replacement, two-scene observed-source isolation, posted-disconnect cleanup, and unrelated automatic-subtree coexistence. EXP-150 rejects render-time current-value observation. EXP-151 accepts one-shot Observation `.didSet` for an existing iOS 27 `@Observable` router whose complete accepted destination is stored in one atomic property, and restores exact synchronous dismissal attribution. EXP-152 confirms actual native Sheet/Cover `onDismiss` callbacks run after accepted Home state and use the fresh occurrences without creating another Home. The low-level EXP-146 publisher remains adapter-author evidence, not the normal customer path. | `EXP-141` 38/38; `EXP-142` 48/48; `EXP-143` restoration 20/20 and canonicalization 19/19; `EXP-144` 43/43; `EXP-145` 19/19; `EXP-146` explicit/capability 42/42 and precedence/lifetime matrix; `EXP-147` migration audit; `EXP-148` 9/9 focused, 153/153 probe, Release build, and final 38/38 local/backend; `EXP-149` 20/20 focused lifetime/scene matrix; `EXP-150` frozen runtime FAIL 17/38; `EXP-151` 8/8 focused, 193/193 broadened, 154/154 probe, Xcode 27 iOS Release plus visionOS package builds, and post-review 38/38 mapper/backend; `EXP-152` 155/155 probe plus clean 38/38 mapper/backend with exact native-callback owners | Automatic discovery is still semantically late and automatic split lacks destination views. A plain current destination is not a trustworthy early signal. Custom/third-party and genuine concurrent two-scene Observation parity; interactive dismissal/cancellation; real OS disconnect/remount/final removal; API review; and hardware coexistence remain. Plain local `@State` and opaque navigation retain automatic/manual fallback rather than an exact claim. |
| UIKit navigation | Push/pop/modal and stock regular-width split transitions create fresh committed occurrences. Interactive cancel retains the current UUID; finish creates a fresh returned UUID. Structural Primary/sidebar columns are not current RUM destinations. | `EXP-079`/`080`, deterministic `EXP-112`, mapper/backend action and Resource ownership | Human edge gestures, subclass containers, adaptive collapse/expand, simultaneous-window completion, and ordinary-app compatibility remain. |
| Manual views | Internal scene stacks and the iOS 27 Swift SPI support exact scene/key start-stop pairing, nested distinct keys, navigation beneath authority, latest-destination reveal, fresh returned occurrences, and crash-safe duplicate-key misuse. Automatic tracking continues outside the target. | `EXP-122`, `EXP-125`-`128`, customer-shaped `EXP-137`-`140` | Same key in A/B with reverse stop is tested hostlessly but live `EXP-129` is simulator-inconclusive. Stable Swift and Objective-C surfaces require review. Legacy source-less start/stop intentionally does not pair with targeted calls. |
| Actions | Source-bearing UIKit/SwiftUI taps emit once; exact-view actions advance the compatibility representative. Manual work inside trustworthy event handoff uses the exact view. A threshold-qualified UIKit scroll remains on its origin across navigation. | `EXP-089`, `EXP-132`, focused routing tests | The decisive visible-A/B representative discriminator needs hardware. Ordinary SwiftUI Button child tasks begin outside the handoff in `EXP-135` and correctly use the approved last-interacted fallback unless explicitly targeted. |
| Resources | Start ownership is captured and completion remains on that scope after navigation or teardown. Manual starts use exact handoff view/scene when available. | `EXP-006`-`009`, `EXP-023`, focused completion tests | Explicit scene targeting and remaining two-window runtime rows are incomplete. Shared/coalesced `EXP-136` is hardware-gated after repeatable simulator-system crashes before completion. |
| Traces and log correlation | Manual/native/OpenTelemetry and URLSession spans share start-context selection. One request survives representative churn; independent A/B requests completed in reverse order keep their start owners. Log correlation and mirrored-error routing have focused scene tests. | Trace-only `EXP-133`/`134` backend spans; latest affected DatadogTrace suite 151/151 | Shared request hardware run, exact-source escape hatch, live two-window log/mirrored-error evidence, and compatibility remain. |
| Errors and view mutations | Manual errors, view attributes, timings, loading-time mutations, and internal view commands prefer exact handoff view then scene then representative. | Focused regressions grouped in `EXP-101` | Targeted public surface and comprehensive two-window mapper/backend runs remain. Raw customer `Error` values must still use sanitized telemetry paths. |
| Operations | Identity is application-wide `(name, operationKey)`. Every step resolves its view independently; navigation can change start/end view. Duplicate starts keep only the latest client start, produce no synthetic end, and leave the earlier backend operation to four-hour timeout. | `EXP-130` raw steps and reduced backend Operations; `EXP-131` 100/100 prepared driver/oracle | Cross-scene success/failure and reverse completion need hardware. Customer view targeting (`.current(in:)` first) is not yet prototyped. |
| Scene lifecycle and restoration | Exact registry, disconnect fencing, retained-reader rearming, migration, explicit session stop, and origin-scene teardown preserve proven ownership in deterministic tests. EXP-146 additionally releases only the exact semantic host and rejects stale post-disconnect starts until fresh lifecycle. | `EXP-008`, `EXP-041`/`042`, `EXP-063`-`066`, `EXP-113`, `EXP-143`; EXP-146 focused disconnect/lifetime tests and synchronous real-reader bounce | Posted notifications and synchronous reader callbacks do not prove genuine OS disconnect or representable remount timing. Final two-window host removal hit the same simulator-system crash twice before removal. Real focus handoff, peer lifecycle, reconnect, isolated background/foreground, and concurrent A/B restoration remain hardware gates. |
| WebView, vitals, fatal/exported context, profiling | WebView native container snapshots and several process/context surfaces have source or focused-test seams. Vitals remain view-based. Profiling operation identity is exact. | Focused module checkpoints and source inspection in the archive | Named runtime/backend scenarios are missing for WebView, vitals, mirrored logs, fatal/exported context, and profiling support statements. Profiling is process-level, not a per-scene view model. |
| Session Replay | Exercised UIKit/SwiftUI two-window and teardown runs uploaded replay data without an SDK-caused crash. | Repeated runtime sessions including `EXP-004` and `EXP-019` | Scene-correct replay representation is explicitly out of scope. Only crash safety is a release requirement here. |
| Single-scene compatibility | Existing inferred/source-less behavior is preserved. Experimental manual and semantic engine/adapter SPIs build at recorded Release checkpoints, and affected suites pass at the latest checkpoint. | DatadogRUM 1,262/1,263 with its sole unrelated timing failure passing immediately in isolation; EXP-151 broadened SDK selection 193/193 and EXP-152 native probe 155/155; RUM view-handler regressions 84/84 at their recorded checkpoint; live opaque, capability, precedence, source-lifetime, reader-bounce, publisher-observed, Observation-observed, and native-callback runs; explicit Xcode 27 iOS Release and visionOS package builds PASS | API-surface verification correctly rejects the unapproved experimental symbols; baselines remain unchanged. Live ordinary automatic/manual apps outside the probe, custom/NOP handler, Objective-C Release, supported-OS, overhead, and reentrancy gates remain. |

## Confirmed capabilities

- Per-scene view ownership survives concurrent creation, navigation, session
  rollover, delayed completion, and originating-scene teardown in exercised paths.
- Returning to the same destination is a new RUM occurrence. The SDK can rotate
  RUM identity without resetting customer SwiftUI state.
- The semantic SwiftUI prototype starts root/destination/presentation occurrences
  at owned materialization boundaries and coexists with automatic tracking without
  duplicate views in the target container.
- The container-independent host can wrap unchanged standard SwiftUI and consume
  a stable adapter source while starting its root before descendant `onAppear`
  and immediate task work. The deterministic probe provides neither a RUM UUID
  nor a native scene identifier. It still manually publishes low-level
  transitions, so this proves the adapter boundary rather than customer effort
  (`EXP-146`).
- The same customer-owned container can expose a stable type-erased capability
  instead of passing the source explicitly and retain the exact 42-event result.
  Without that capability, the host leaves automatic capture active, emits no
  synthetic semantic view, and remains crash-safe; it cannot infer exact
  destination semantics from opaque content (`EXP-146`).
- An explicit source overrides a contradictory capability at runtime. Repeated
  capability resolution during SwiftUI reconstruction does not replay state, and
  a later resolution that returns an adversarial source cannot replace the first
  source selected by the host. All three discriminators preserve the complete
  semantic timeline and exact backend ownership (`EXP-146`).
- One-shot Observation `.didSet` over a single atomic accepted-destination
  property can notify the semantic adapter and rearm before the router setter
  returns. Sequential and nested mutations, SwiftUI reconstruction, teardown,
  and invalid off-main mutation remain crash-safe in focused coverage; the
  post-review runtime assigns immediate and settled sheet/cover dismissal work
  to fresh revealed occurrences (`EXP-151`).
- After a standard Sheet or full-screen cover has actually appeared, its native
  SwiftUI `onDismiss` callback runs after the accepted Home mutation. Each
  programmatic callback fires once, creates no extra Home, and its immediate and
  settled action/Resource pairs use the fresh revealed occurrence (`EXP-152`).
- Sequential repeated equal route values retain distinct materialized occurrence
  claims while preserving ordinary `NavigationLink(value: Route)` matching.
- A directly restored repeated-equal path materializes only its top on iOS 27;
  removing that position rebases the boundary to a fresh surviving occurrence,
  without publishing hidden root or lower-route views. The accepted top starts
  before hidden-root lifecycle work, and reliable replacement readers can adopt
  or recover ownership across descriptor lag, disconnect, reuse, and scene move.
- External router replacement emits only accepted same-type and different-type
  destinations. A rejected proposal emits no view. If a binding canonicalizes a
  proposed value, only its getter result becomes current and starts before the
  accepted destination's `onAppear` and immediate task work.
- Direct semantic presentation replacement is atomic in both exercised
  directions: H1 → Sheet S1 → Cover F1 → Sheet S2 → fresh H2. The underlying
  stack destination is never briefly current between presentations.
- The actual semantic SPI preserves sibling-controller containment. Right-side
  Detail commits beneath left manual authority without becoming current, then
  starts once as a fresh semantic occurrence after authority stops (`EXP-145`).
- A manual authority suffix can hide underlying navigation, reveal only its latest
  committed destination fresh, and nest Compose → Preview → fresh Compose.
- UIKit interactive cancellation and completion are committed-transition
  semantics, and regular split Primary/sidebar surfaces are structural context.
- Source-bearing actions and captured Resource/Trace starts retain exact ownership;
  source-less work keeps the existing last-interacted representative behavior.
- Operation start/end views may differ, identities are not scene-namespaced, and
  duplicate-start behavior matches the approved backend timeout contract.
- Scene state is internal and suitable for future Execution Context mapping
  without changing today's wire format.

## Confirmed gaps and failure modes

1. Automatic native SwiftUI discovery can start after `onAppear`/immediate
   `.task` work, identify framework containers instead of semantic routes, and
   leak the prior scene into a newly opened window (`EXP-021`, `022`, `028`,
   `069`, automatic control in `EXP-111`).
2. `EXP-143` through `EXP-146` close direct repeated restoration, external router
   replacement/rejection/canonicalization, presentation-to-presentation
   replacement, actual-SPI sibling isolation, the container-independent engine,
   arbitrary-content host, stable explicit source, optional capability, and
   opaque automatic fallback, runtime precedence, repeated reconstruction, and
   adversarial source replacement at the engine/adapter boundary. EXP-146 also
   passes a synchronous real-reader bounce and focused disconnect fence, while
   its final-removal runtime is simulator-inconclusive before removal. `EXP-147`
   closes the migration-cost discriminator for an application with existing
   observable routers: 25 routes, seven presentations, three exact router
   boundaries, two automatic-fallback boundaries, zero screen edits, zero of
   twelve navigation-method edits, and zero RUM-code growth for one added route
   and presentation. `EXP-148` moves that policy into DatadogRUM and passes the
   same 38/38 semantic/backend oracle. It also fixes equal-route deduplication,
   pre-first-value authority, background-delivery ordering, and pending-source
   precedence. `EXP-149` closes actual host subscription reconstruction,
   publisher replacement, two-scene observed-source isolation, posted-disconnect
   fencing, and unrelated automatic-subtree coexistence at 20/20. `EXP-150`
   conclusively rejects a value sampled only during SwiftUI reconstruction: its
   frozen run fails 17/38 and backend intake keeps immediate dismissal work on
   the outgoing presentation. `EXP-151` accepts one-shot Observation of one
   atomic accepted-state property: 8/8 focused tests, 193/193 affected SwiftUI
   tests, 154/154 probe tests, iOS Release and visionOS builds, and a post-review
   38/38 runtime/backend run with exact immediate dismissal ownership. `EXP-152`
   separately waits for actual Sheet/Cover content appearance and then passes
   38/38 locally and in backend intake: both native callbacks see accepted Home,
   create no extra occurrence, and use fresh H3/H4. Custom/third-party and
   genuine concurrent two-scene parity remain before public review; interactive
   gesture dismissal and genuine OS disconnect/remount remain hardware-gated.
3. Stable simultaneously visible/interactive windows cannot be proven by this
   simulator. Repeated Metal/`backboardd` failures are environment boundaries, not
   SDK crash evidence.
4. Ordinary SwiftUI Button child tasks are outside the `sendEvent` handoff in the
   measured path. Exact origin cannot be inferred after suspension; `EXP-135`
   intentionally preserves the approved B/last-interacted fallback.
5. Scene-targeted Operation completion and other explicit downstream APIs remain
   prototypes-to-build, and cross-window runtime acceptance is pending.
6. Activation, peer backgrounding, reconnect, per-scene lifecycle, and concurrent
   restoration are incomplete.
7. Errors, logs, WebView, vitals, fatal/exported context, and profiling lack the
   same depth of live two-window/backend evidence as views, Resources, and Traces.
8. Full normal-app, custom-handler, Objective-C Release, supported-system, and
   performance/reentrancy validation has not run on the final code shape.

## Compatibility and regression risks

| Risk | Required protection |
| --- | --- |
| Global automatic suppression | Authority must be contained by exact scene/controller ancestry; detached or sibling trackers cannot suppress unrelated views. |
| Source-less behavior drift | Legacy APIs keep last-interacted/process representative behavior. An unresolved explicit target falls through safely rather than dropping work. |
| Route identity leaking into customer state | Never wrap or replace the customer's route element type. RUM occurrence identity stays private to materialized boundaries. |
| Datadog-specific navigation migration | Keep the semantic engine independent of visual containers. Standard SwiftUI/UIKit/custom navigation and presentation code remains owned by the customer. EXP-147 proves one boundary per existing router, zero screen and navigation-method edits, automatic metadata, sparse overrides, and no route/presentation-growth cost; EXP-148 preserves that budget in the SDK-owned prototype. Neither experiment approves stable API names. |
| Unstable optional capability | Use a stable type-erased transition source across SwiftUI value reconstruction. An explicit source wins over detected capability; an opaque container degrades to automatic tracking rather than fabricated semantics. |
| Uncommitted navigation | A path proposal, speculative callback, or cancelled transition cannot create a view. Reconcile against accepted path and transition completion. |
| Retained/stale scene state | Retain snapshots only as fallbacks; fence disconnected callbacks and never resurrect a live scope from stale UI objects. |
| Swizzle and event-handoff safety | Preserve repository swizzling rules, reentrancy, main-thread constraints, bounded work, and no customer-app crashes. |
| Custom conformers/NOP initialization | New capabilities must fall back exactly once and remain source-compatible when the core or specialized handler is unavailable. |
| Older systems | Gate iOS 27 APIs. Multi-scene semantics may be unavailable earlier, but existing iOS 15-26 apps must build and behave as before. |
| API/wire stability | No internal UUID exposure, returned view handle, temporary scene attribute, session split, generated-model edit, or endpoint change. |
| Replay coupling | Multi-scene RUM changes cannot crash Session Replay; replay correctness does not drive this design. |

## Evidence confidence and latest validation

Evidence strength is intentionally separated:

| Tier | What it proves |
| --- | --- |
| Source | A path exists or a platform/API limitation is understood; it does not prove runtime attribution. |
| Focused test | State transitions, fallbacks, identity, and adversarial oracle behavior are deterministic. |
| Local/mapper | The intended UI path occurred and the SDK assigned concrete RUM UUID ownership. |
| Backend | Intake and, for Operations, reduction represented the emitted ownership. |
| Physical/human | The topology or analog gesture unavailable to deterministic simulator control actually occurred. |

Latest authoritative checkpoint. All `EXP-146` transition-source entries below
are engine/adapter proofs; none is evidence that normal customers should publish
every transition manually:

- Accepted `EXP-146` explicit-source run
  `semantic-host-explicit-20260916-b`: 42/42, exact ApplicationLaunch/H1/D1/H2/
  Sheet/H3/Cover/H4 inventory, 26 actions, 26 Resources, five long tasks, one
  session, one vital, and zero errors/crashes. ApplicationLaunch owns no action or
  Resource after the initial-lifecycle fix. All four Home occurrences have distinct
  IDs and standard SwiftUI navigation/presentation call sites are unchanged. Host
  implementation `a84061840`; probe/oracle `354422d88`.
- Accepted `EXP-146` optional-capability run
  `semantic-host-capability-20260916-a`: 42/42, the same eight-view semantic
  inventory, 26 actions, 26 Resources, no automatic duplicate, and zero
  errors/crashes. Accepted opaque run
  `semantic-host-automatic-fallback-20260916-b`: 5/5, four automatic-era views,
  six actions, six Resources, no semantic-origin view, and exact Detail delayed
  ownership on `NavigationStackHostingController<AnyView>`. Matrix commit
  `651b173c6`.
- Accepted `EXP-146` runtime precedence and source-lifetime runs:
  `semantic-host-explicit-precedence-20260916-a`,
  `semantic-host-capability-reconstruction-20260916-a`, and
  `semantic-host-capability-replacement-20260916-a` each pass 43/43. Their
  backend sessions `174b4c5c-a7dd-4cee-ab4f-dc0be8ca9c62`,
  `24dd4a46-4a6f-4caf-93e1-77685425e7dc`, and
  `4841bf45-25ac-4f63-ac2c-1de934ef9d3b` each contain launch plus seven unique
  semantic occurrences, 26 exact-view actions, 26 exact-view Resources, no
  decoy/automatic duplicate, and no error event. Probe commit `47bc08eca`.
- Accepted deterministic lifetime run
  `exp146-transient-reader-reattach-20260916T034534Z`: 17/17, session
  `fe33be6f-b953-4c9a-abce-aae37bdb2ef5`. One Detail UUID survives the
  synchronous detach/reattach delivered through the real SDK reader; a later
  source commit creates fresh Home H2, and backend action/Resource owners match.
  This proves generation cancellation, not actual representable remount timing.
- Focused scene-disconnect and lifetime handling passes all 84
  `RUMViewsHandlerTests`: stale A starts are fenced until fresh scene lifecycle,
  A's semantic source and suppression are released, and B remains usable. Posted
  lifecycle notifications are deterministic internal evidence, not a genuine OS
  disconnect run.
- Final-host-removal runs `exp146-final-host-removal-20260916T035341Z` and
  `exp146-final-host-removal-20260916T035545Z` are simulator-INCONCLUSIVE. Both
  clean attempts hit the same `backboardd` Metal/CoreAnimation SIGABRT after B
  became ready and before host removal; neither produced an app crash, terminal
  result, upload, or backend event. The unchanged row is now hardware-only.
- Closed `EXP-145` semantic sibling run
  `semantic-sibling-isolation-20260916-fix-c`: 19/19, exact
  ApplicationLaunch/H1/manual-authority/D1 inventory, 11 actions, 11 Resources,
  two long tasks, one session, one vital, and zero errors/crashes. No automatic
  destination starts, D1 begins only after manual authority, and all active/
  post-stop work uses the expected UUID. Probe/oracle commit `144d6e0e7`.

- Closed `EXP-144` bidirectional run
  `semantic-presentation-bidirectional-20260916-fix-b`: 43/43, exact
  ApplicationLaunch/H1/S1/F1/S2/H2 inventory, 19 actions, 19 Resources, two
  long tasks, one session, one vital, and zero errors/crashes. Every action and
  Resource is grouped on its exact occurrence. SDK implementation `698b1584d`;
  bidirectional probe `01a8466c5`. Exact session and event IDs are in the active
  `EXP-144` record.
- Closed `EXP-143` canonicalized-write and restored-path runs remain accepted at
  19/19 and 20/20 with exact backend ownership.
- `EXP-142` accepted run: 48/48, exact H1/D1/D2/fresh D3/fresh H2
  ownership, 55 backend events (24 actions, 22 Resources, six views including
  ApplicationLaunch, one long task, one session, one vital), zero error/crash,
  and six HTTP 202 uploads.
- Accepted `EXP-151` post-review run
  `exp151-observation-router-postreview-20260916T083131Z`: 38/38 with exact
  ApplicationLaunch/H1/D1/H2/Sheet/H3/Cover/H4 inventory. Backend session
  `ea9adc0e-5a00-4290-9580-fb4df6bc18e7` contains eight views, 11 actions,
  11 Resources, five long tasks, one session, one vital, and no error bucket or
  crash. Immediate and settled sheet dismissal work owns fresh H3; immediate
  and settled cover dismissal work owns fresh H4. The frozen source hashes are
  recorded in the active experiment record.
- Accepted `EXP-152` native-callback run
  `exp152-native-dismiss-callbacks-20260916T094300Z`: 38/38 with each Sheet and
  cover content-appearance and actual `onDismiss` assertion firing exactly once.
  Backend session `fee27d61-1eb7-4eb6-8525-7af74a53ed7e` contains eight views,
  11 actions, 11 Resources, seven long tasks, one session, one vital, and zero
  errors/crashes. Both immediate and settled Sheet callback pairs own fresh H3;
  both cover pairs own fresh H4; no callback creates another Home.
- Signed SDK implementation/test checkpoint `24cf5078a`; signed migration
  fixture, harness, and probe-test checkpoint `7da52ae6d`; signed EXP-152
  harness checkpoint `0a67f3e36`.
- EXP-151 focused Observation/adapter tests: 8/8. The complete affected SwiftUI
  test file passes 193/193, including nested reentrancy, `StateObject`
  reconstruction, independent-property semantics, deallocation, and invalid
  background-mutation crash safety.
- Native multi-scene probe: 155/155.
- Complete DatadogRUM suite: 1,262/1,263; the sole unrelated timeseries timing
  failure passed immediately in isolation.
- API-surface verification reports only the expected unapproved experimental
  navigation/manual symbols; neither checked-in baseline is changed.
- Focused semantic presentation replacement: 3/3.
- Final semantic navigation state/source/arbiter cluster: 153/153. The final
  trait path additionally proves it cannot move or recover a scene without its
  prior concrete reader attachment.
- DatadogTrace: 151/151 at the latest Trace-affecting checkpoint.
- Xcode 27 generic iOS Release and visionOS package builds succeed. Current
  repository SwiftLint is clean across 713 source and 699 test files. Unaffected
  module suites remain at their recorded checkpoints and must rerun at final
  freeze.
- `EXP-141` independently has seven semantic occurrences, 25 exact-view actions,
  25 exact-view Resources, and zero errors/crashes.
- Frozen archives preserve every run ID, session ID, UUID, commit, scenario,
  failed attempt, and earlier suite count; their checksums are in
  [Archive/README.md](Archive/README.md).

No hardware row is promoted from simulator evidence. `EXP-039` remains a
deterministic-harness gap rather than a device queue item because its candidate
was never constructed.

## Release blockers

P0 blockers:

1. Prove custom/third-party and genuine two-scene adapter parity after EXP-151
   accepted the atomic Observation input, EXP-152 closed programmatic native
   callback timing, and EXP-149 closed the
   deterministic subscription-reconstruction, two-scene isolation, and posted-
   disconnect matrix. Do not weaken the accepted zero screen/navigation-method
   edit budget. Optional capability and opaque fallback remain engine-boundary
   evidence until the parity matrix distinguishes exact and best-effort paths.
2. Prototype and validate scene-aware Operation targeting, then the required
   downstream target surfaces without changing legacy fallback.
3. Close actual semantic-host removal and genuine scene disconnect/reconnect,
   then pass the rest of the P0 [physical-device and human-driven
   queue](PLAN.md#physical-device-and-human-driven-queue), including semantic A /
   automatic B, same-key manual A/B, cross-scene Operations, shared Trace, exact
   activation, visible-A action attribution, and human cancel/finish gestures.
4. Close ordinary single-scene/custom-handler behavior, overhead/reentrancy,
   supported-system, full suite/lint/API surface, and Objective-C Release gates.
5. Pass the final iPhone Duo iOS 27.1 matrix with mapper and backend evidence and
   no SDK-caused crash.

P1/claim-bounding work:

- adaptive split resize and concurrent restoration;
- targeted runtime evidence for errors, logs, WebView, vitals, fatal/exported
  context, and profiling;
- document automatic SwiftUI limits and process-level profiling boundaries; and
- confirm Session Replay remains crash-safe without claiming replay correctness.

## Evidence routing

- Ordered work and hardware queue: [PLAN.md](PLAN.md)
- Searchable experiment status: [EXPERIMENTS.md](EXPERIMENTS.md)
- New detailed records: [Experiments/EXP-143-199.md](Experiments/EXP-143-199.md)
- Historical exact evidence: [Archive/EXPERIMENTS_THROUGH_EXP-142.md](Archive/EXPERIMENTS_THROUGH_EXP-142.md)
- Rejected paths: [REJECTED_APPROACHES.md](REJECTED_APPROACHES.md)
- SwiftUI/manual API contract: [NAVIGATION_API.md](NAVIGATION_API.md)
- Operation contract: [OPERATIONS.md](OPERATIONS.md)
- Tool workflow: [TOOLING_RUNBOOK.md](TOOLING_RUNBOOK.md)
