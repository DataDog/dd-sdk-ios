# RUM multi-scene implementation and validation plan

Read this document when choosing or executing the next implementation slice,
extending the probes, or checking the release gates. Evidence and current support
levels live in [ASSESSMENT.md](ASSESSMENT.md); chronological run details live in
[EXPERIMENTS.md](EXPERIMENTS.md); public navigation/manual-view review starts in
[NAVIGATION_API.md](NAVIGATION_API.md). Start at the
[canonical overview](../MULTI_SCENE_SUPPORT.md) for the current resume point.

Evidence references use the stable `EXP-*` identifiers from the experiment
ledger; exact run and session identifiers remain in `EXPERIMENTS.md`.

Last updated: 2026-09-14

## Experimental application plan

The probe must use the SDK sources in this checkout and real local RUM
configuration. Every run will use a unique run identifier attached to events so
that console output, locally observed payloads, and backend sessions can be joined
without relying on timestamps alone.

The current runner is a UIKit scene-delegate host. Its default mode uses
`.trackRUMView`; setting `DD_MULTI_SCENE_SWIFTUI_VIEW_TRACKING=automatic` removes
those modifiers and enables `DefaultSwiftUIRUMViewsPredicate`. The first automatic
run is intentionally retained as a failing semantic baseline. Before claiming
transparent SwiftUI support, turn its late destination and transient-root sequence
into focused regressions. The standalone native SwiftUI `@main`/`WindowGroup`
host under `Datadog/Example/MultiSceneProbe` now reproduces that sequence and the
cross-window startup leak using `openWindow`; it is the primary fix-validation
harness. Its default remains the automatic failing baseline. Setting
`DD_MULTI_SCENE_SWIFTUI_VIEW_TRACKING=manual` disables automatic discovery and
    wraps semantic Home and Detail roots with `.trackRUMView`; the optional
    `tab-preload` stress mode registers an explicitly tracked unselected tab. Split
    navigation controls now exist. Before running the remaining downstream rows,
    add the controls still missing for restoration, WebView, mirrored
    `logger.error`, fatal context, and exported RUM-context inspection.

The minimum probe contains two independently identifiable windows. Each window
must expose:

- its scene/session label and current screen;
- UIKit push, pop, present, and dismiss controls;
- SwiftUI `NavigationStack` push/pop and modal controls;
- uniquely named tap and scroll actions;
- a request with a unique URL/query marker and a traced request;
- manual error, timing, feature-operation, and long-running task controls where
  APIs permit;
- controls to open a new window and close the current one.

The view, navigation, action, and lifecycle sequences remain required:

1. Open A, then B, leaving both visible.
2. Alternate navigation A-B-A-B without closing either window.
3. Tap and scroll in the non-most-recently-opened scene.
4. Background and foreground only one scene while another remains visible.
5. Disconnect B and continue navigation in A.
6. Reconnect/restoration where the platform preserves a scene session.
7. Repeat with duplicate screen/view names in A and B.
8. Repeat representative flows for UIKit, SwiftUI `NavigationStack`, modals, and
   `NavigationSplitView`.

The Resource/Trace causal-boundary matrix must use two visible scenes and actual
URLSession interception, not only command or TaskLocal unit tests:

1. A synchronous request directly inside a UIKit tap.
2. `Task {}` created inside a tap, before and after suspension.
3. `Task.detached`, `DispatchQueue.async`, and `Timer`.
4. A SwiftUI `Button` followed by `Task {}`.
5. SwiftUI `.task` and `onAppear` loading.
6. Scene connection and `viewDidAppear` loading.
7. A pre-created `URLSessionTask` resumed from a UI action.
8. One shared/coalesced request used by both scenes.
9. Navigation and session rollover before the request actually starts.
10. Reverse-order completion from the two scenes.
11. Originating scene closure before completion.
12. Trace-only URLSession spans.
13. An automatically detected action accepted versus rejected by its predicate or
    by an already-active action.
14. Single-scene regressions and ordinary third-party URLSession-handler
    compatibility.

For every case, record whether provenance should exist, then verify emitted view
ID, action ID, session ID, resource ID, and trace correlation in console payloads
and backend intake. Unknown-provenance cases pass by being explicitly classified
and following the chosen compatibility policy, not by accidentally matching the
representative window. A build, callback count, TaskLocal unit test, or absence of
crashes is not sufficient semantic evidence.

### Device and human validation routing

Do not spend simulator time retrying interactions or topologies it cannot
express. The authoritative rerun queue is in
[EXPERIMENTS.md](EXPERIMENTS.md#real-device-and-human-driven-rerun-queue). Route
native SwiftUI and UIKit edge-pop cancellation to a human on a physical device;
route simultaneous visible-window navigation, representative discrimination,
peer-window close, adaptive resize, and two-scene restoration to iPhone Duo or a
physical iPad topology that exposes the needed state. An agent should still own
the deterministic setup, unique run ID, console/payload capture, and backend
verification. A human gesture closes a row only when path, coordinator, lifecycle,
and RUM UUID evidence distinguish it from an ignored touch.

## Implementation plan

Current execution order:

No product decision blocks the remaining internal work. Complete-destination
Sheet/full-screen-cover behavior, sibling-container isolation, and one-scene
nested-manual/duplicate-start behavior now pass; public names and exact
Swift/Objective-C signatures remain gated on normal API review. The exact
two-scene same-key contract is implemented and passes hostless tests, but its
live acceptance is now in the physical-device queue. The exact cross-scene
Operation driver is also implemented through `EXP-131`; its 100/100 hostless
contract is ready for the same hardware gate.

1. Completed in `115dc9e38` and `EXP-109`: connect observable scene, route,
   destination, and RUM-occurrence acknowledgements to the recorder and oracle.
   Three clean Home → Detail → Home runs each produced one 7/7 local `PASS` before
   matching backend confirmation; the probe plan passes 35/35. Keep harness and
   production SDK commits separate.
2. Completed in `116220bed` and `EXP-110`: drive stack abort and
   same-/different-type replacement through exact observed signals, with decisive
   final action/Resource checks. Clean reruns passed 5/5, 6/6, and 6/6 locally
   and in backend intake; the probe plan passes 37/37.
3. Completed in `38b6868a3` and `EXP-111`: drive split selection and retained
   return through exact scene/selection/destination signals. Route-owned runs pass
   10/10 and 13/13 locally and in backend intake; the automatic control fails 0/9
   with launch/internal-container ownership; the probe plan passes 40/40.
4. Completed in `a001c8377`, `35e53ba30`, and `EXP-112`: drive UIKit cancel and
   finish through exact transition begin/progress/resolution signals and suppress
   regular-width structural Primary/supplementary views on the iOS 27 multi-scene
   path. Clean runs pass 11/11 and 13/13 locally and in backend intake; the probe
   plan passes 42/42 and the complete RUM plan passes 1,153/1,153. Keep native
   gesture proof in the real-device/human queue.
5. Harness portion completed in `0234183e0`, `853f90648`, `EXP-113`, and
   `EXP-114`: exact A-to-B open waits for B readiness, exact B close waits for B
   disconnect, and subsequent A work stays on A's original Home occurrence.
   Exact activation dispatch waits for target foreground state, and peer lifecycle
   waits treat the latest non-superseded state as a condition rather than assuming
   notification order. Missing peer background is `INCONCLUSIVE`. The probe plan
   passes 45/45. Stable simultaneous-visible activation and peer continuity now
   require iPhone Duo or a physical multi-window iPad; do not keep retrying the
   compositor-crashing loop on this simulator.
6. Prototype completed in `4fc9d91b3`, `93cbb3387`, `3cdb4b915`, and
   `EXP-115`/`EXP-116`/`EXP-118`:
   automatic tracking stays enabled, an active attached explicit subtree
   suppresses only its containing automatic candidate, and a probe-only
   `NavigationStack` wrapper consumes one bound application path plus one
   centralized RUM resolver. It owns root/destination materialization so the
   existing early route boundary still handles return, abort, and same-type
   replacement correctly. The scene-selective `EXP-118` discriminator leaves
   semantic tracking only in A and requires B work to resolve to an automatic
   view first observed after B opens. Two clean simulator prefixes created B's
   own automatic views without disturbing A, but `backboardd` aborted before the
   final marker and oracle. Finish that exact row when physical hardware is
   available; meanwhile, write the RFC/API proposal and continue independent
   simulator-capable experiments. No public API lands without normal review.
7. Presentation slice completed in `f452e9e3f`, `fad83f58f`, `c70920c94`, and
   `EXP-123` through `EXP-126`. The exact-scene router publishes the semantic
   Sheet or full-screen-cover M1 while a UI-attached
   suppression-only state excludes only its automatic presentation controller
   until native dismissal. Separate clean runs each pass 14/14 with H1 -> M1 ->
   fresh H2, no automatic presentation duplicate, and immediate plus settled
   dismiss work on H2. `EXP-124` proves an outgoing aggregate's delayed final
   snapshot is not an authority interval. The Sheet backend set has 29 events;
   full-screen cover has 28; both report zero errors or crashes.
8. Completed as a negative discriminator in `56969d8a5` and `EXP-120`: direct
   keyed manual start/stop over automatic H1 does not provide manual authority.
   Automatic discovery displaced M1 within 31–48 ms, and the intended M1
   action/Resource used the automatic fallback. Eventual H2 restoration is too
   late. The probe plan passes 65/65 after hardening its authority interval and
   exact-owner fixtures.
9. Completed in `29c8cec2c`, `b1a0fb6b8`, `a40e7903c`, `EXP-121`, and
   `EXP-122`: exact-scene manual entries now use `RUMViewsHandler`, keep the
   complete manual suffix authoritative, stage legitimate automatic candidates,
   apply stop attributes, and reveal a fresh underlying occurrence on exact
   scene/key stop. The first live run fixed M1 preemption but exposed a generic
   fallback reveal. The hardened run passes 16/16 with H1 -> M1 -> fresh H2,
   exact active/immediate/settled ownership, and matching backend intake. Existing
   source-less APIs remain on their inferred direct-command path.
10. Internal contract completed in `f452e9e3f`: several navigation commits
    beneath M1 emit no intermediate view and reveal only the latest destination;
    stopping nested Preview starts a fresh Compose occurrence; duplicate active
    `(scene, key)` start is ignored crash-safely without restart; and existing
    source-less behavior remains separate. The focused presentation/manual set
    passes 6/6. The same key must coexist independently in A and B and a stop must
    affect only its exact scene/key. Public overloads still require API review.
11. Completed in `45ec5656a` and `EXP-127`: prove container-local authority with
    two independently materialized `NavigationStack` controller branches under
    one outer SwiftUI host. A mandatory ancestry witness distinguishes the real
    siblings before the oracle can pass. Left manual M1 remains current while
    right Home commits to Detail underneath; exact stop reveals only fresh Detail,
    and immediate plus settled work uses it. Two clean runs pass 19/19; the final
    backend session has exactly four views and 11 action/Resource pairs with zero
    errors or crashes. The probe plan passes 76/76.
12. Completed in `EXP-128`: exercise a real distinct-key manual suffix and a
    duplicate active key. The clean run passes 29/29 with H1 -> C1 -> P1 -> fresh
    C2 -> fresh H2. Duplicate Compose creates no restart and leaves its
    action/Resource on C2. The first attempt exposed a driver race when C1 was
    recorded before its wait step; immutable exact-view waits now accept prior
    evidence. The probe plan passes 83/83 and backend intake agrees with no error
    or crash.
13. Harness and simulator prefix completed in `EXP-129`: the exact same-key A/B
    scenario starts `compose` in each scene, stops B before A, and rejects shared
    UUIDs, cross-scene work, wrong-scene stop effects, and reused returned Home
    occurrences. The probe plan passes 91/91. The explicitly uninstalled
    simulator run reached both native scenes, then lost the Xcode/device session
    before manual authority began; it has no terminal or backend result. Do not
    repeat this topology on the simulator.
14. Completed in `5d536e0bd` and `EXP-130`: drive successful and failed
    Operations across fresh Home→Detail occurrences, then start one duplicate
    identity before navigation and again after navigation. The scenario passes
    27/27 and the full probe plan passes 93/93. Backend intake preserves H1→D1
    success and H2→D2 failure, while the duplicate emits `[start H3, start D3,
    end D3]`, reduces from D3, and leaves H3 open without a synthetic end. The
    corrected warning and zero error/crash result are captured.
15. Finish `swiftui.coexistence.same-key-manual-two-scenes` and
    `swiftui.coexistence.semantic-a-automatic-b` on physical multi-window
    hardware. Require each terminal oracle and exact backend owners; neither
    partial simulator prefix is acceptance evidence.
16. Take the scene-aware Swift/Objective-C manual-view overloads through API
    review while preserving the existing inferred/last-interacted APIs.
17. Close the primary action-attribution hardware row: hold A and B visibly
    active, make B the representative, interact in A without a focus transition,
    and prove the action plus its immediate Resource use A. Repeat UIKit drag and
    deceleration and require one action on the originating view occurrence.
18. Completed in `a653e29f2` and `EXP-131`: prepare exact A-to-B Operation
    success/failure plus same-name, distinct-key parallel Operations completed
    B-before-A. The driver and adversarial ownership oracle pass in the 100/100
    hostless plan. Run the unchanged scenario on capable multi-window hardware
    and require eight raw steps plus four correctly reduced Operations.
19. Run `windows.activation-sequence` on iPhone Duo or a physical multi-window
    iPad, requiring exact foreground-active target and background peer state.
20. After API approval, land the optional complete-destination SwiftUI semantic
    integration with centralized path/router metadata, presentation coverage, and
    target-local automatic deduplication.
21. Obtain recognized native SwiftUI cancel/finish gestures, preserve the retained
    split result through adaptive collapse/expand, and validate stable simultaneous
    A/B topology through the real-device/human queue.
22. Run genuine disconnect/reconnect, per-scene background/foreground, and
    concurrent restoration.
23. Complete Operation public targeting; duplicate-start backend behavior is
    already closed by `EXP-130` and must not be rerun as an A-to-B prerequisite.
24. Close the bounded Resource/Trace and downstream rows, live single-scene and
    custom-handler compatibility, handoff overhead, and iOS 27.1/iPhone Duo matrix.

This order implements the approved product priority: view occurrences and
navigation first, then scene-aware manual views, downstream ownership,
compatibility, and Session Replay crash safety. Work that requires physical
topology can run later without allowing lower-priority SDK design to replace it.

This plan was rechecked against the original objective and the approved product
decision record after `EXP-129`. It still
covers proper per-scene view creation, SwiftUI and UIKit navigation, action
ownership, Resources/Traces/Operations and the remaining downstream signals,
single-scene compatibility, and Session Replay crash safety. Header injection for
developer-rewritten requests, true multi-pane/tab modeling, and Execution Context
serialization remain deliberately outside this project. Hardware-limited
activation evidence is queued rather than allowed to block the next view/navigation
implementation slice.

The UIKit split and exact-owner fixes remain regression gates, but they no longer
precede the automatic SwiftUI P0. Device-limited rows are routed through the
real-device/human queue instead of repeated on the current simulator.

### Deterministic probe harness workstream

This workstream improves the reliability and handoff cost of every remaining
experiment; it does not itself change the SDK support verdict.

1. Completed in `41029e1e3` and `EXP-106`: a validated 35-scenario catalog lives
   under `MultiSceneProbe/Sources/Harness`. Command-line selection is primary, the
   temporary environment adapter accepts only exact non-contradictory profiles,
   and the complete manifest is emitted before Datadog starts. Invalid launches
   fail closed. The generated hostless target currently passes 15/15 tests.
2. Completed in `e70e5ca51` and `EXP-107`: record versioned JSONL signals and
   evaluate them with a pure semantic oracle.
   The only results are `PASS`, `FAIL`, `SKIPPED`, and `INCONCLUSIVE`; ordered and
   negative expectations must distinguish wrong attribution, missing events,
   cancelled transitions, ignored gestures, and unsupported capabilities. The
   generated probe test plan passed 24/24 at that checkpoint, including correct
   return, wrong-view, ignored-gesture, missing-event, and forbidden-event
   fixtures. The
   mapper records pre-persistence RUM snapshots; call-site source labels are never
   treated as ownership. A live ApplicationLaunch → Home → Detail prefix agrees
   with backend intake, but is not yet a live oracle PASS.
3. Completed in `af18679f2` and `EXP-108`: one main-actor scene registry keeps
   stable logical labels, exact native session identifiers, weak windows,
   activation, geometry/size classes, route, readiness, and disconnection
   generation. It rejects aliasing and stale handles, and its internal future
   Window Execution Context seam is not serialized. The probe plan passes 31/31;
   a clean iPadOS 27 run and backend session validate the Home → Detail prefix.
   At that checkpoint exact activation remained part of the lifecycle-driving
   phase. Exact open/close runtime proof is completed by `EXP-113`; activation
   driving is completed by `EXP-114`, while its hardware runtime proof stays open.
4. Initial slice completed in `115dc9e38` and `EXP-109`: drive
   `swiftui.stack.return` through observable scene, path, destination, and
   RUM-occurrence acknowledgements. The driver emits exactly one terminal result,
   all 35 tests pass, and three clean iPadOS 27 runs each passed 7/7 locally and
   in backend intake. View-stop mapper snapshots may arrive after the next view
   start during animation, so the oracle requires those eventual lifecycle facts
   without mistaking callback order for navigation order. Keep deterministic
   state-machine proof separate from genuine native gesture proof; a drag without
   transition/path recognition is `INCONCLUSIVE`.
5. Completed in `116220bed` and `EXP-110`: extend the signal-driven loop to stack
   abort and same-/different-type replacement. The decisive final action and
   Resource are part of each semantic timeline. The complete probe plan passes
   37/37; clean iPadOS 27 runs pass locally and in backend intake without errors.
6. Completed in `38b6868a3` and `EXP-111`: root-owned split selection now executes
   through the exact scene and waits for observed selection and destination
   signals. Route-owned replacement and retained return pass 10/10 and 13/13 with
   exact per-occurrence action/Resource ownership; the automatic baseline fails
   0/9 with internal container views. Resource completion is an eventual ownership
   fact, not a navigation-order clock, and completion conditions skip earlier
   same-named occurrences. The complete probe plan passes 40/40.
7. Completed in `35e53ba30` and `EXP-112`: UIKit cancel/finish commands execute
   against the exact registered scene. The driver separately observes transition
   begin, exact progress, resolution request, and coordinator result. Cancellation
   retains S2; completion requires fresh returned S1; both require final exact
   action/Resource ownership. The complete probe plan passes 42/42.
8. Completed in `0234183e0` and `EXP-113`: `open-window` requires an exact source
   and target, dispatches only through the source executor, and acknowledges the
   target's readiness. `close-window` dispatches through the exact target and
   acknowledges its disconnect. The close scenario requires B's pre-close
   Resource and A's post-close action/Resource on their first Home occurrences.
   One clean iPadOS 27 run passes 9/9 locally and in backend intake; the complete
   probe plan passed 43/43 at that checkpoint. Activation driving was completed
   next; simultaneous-visible topology proof remained open.
9. Completed in `853f90648` and `EXP-114`: `activate-window` dispatches through
   the exact registered `UIWindowScene` and waits for its foreground-active
   lifecycle state. The activation scenario requires the peer to become background
   before it asserts a new occurrence or marker ownership. Scene-state waits use
   the latest exact-scene lifecycle snapshot, so a valid notification that arrives
   before target activation is not lost; a superseded or missing state cannot
   pass. Missing topology is `INCONCLUSIVE`, and the terminal JSON result is also
   written to OSLog. One compatibility-control run reached backend intake and
   showed source-less A-labelled markers correctly staying on representative B;
   lifecycle-gated retries were simulator-inconclusive, including one interrupted
   by a `backboardd` CoreAnimation/Metal crash. The probe plan passes 45/45.
10. Completed in `4fc9d91b3` and `EXP-115`: enable automatic SwiftUI discovery
   during the signal-driven explicit occurrence scenario. The authority registry
   uses active attached view containment, leaves sibling controllers eligible,
   and does not affect UIKit predicate acceptance. One clean iPadOS 27 run passes
   7/7 locally and produces exactly launch plus H1/D1/H2 in backend intake, with
   no hosting-controller duplicate. The RUM plan passes 1,157/1,157 and the probe
   remains 45/45. This proves internal coexistence, not the reviewed container API.
11. Prepared in `3cdb4b915` and `EXP-118`: configure semantic navigation only in
   scene A while automatic discovery remains enabled application-wide, open B
   exactly, and require B's decisive marker to use a non-launch automatic view
   first observed after the open command. Four source/owner and stale-view oracle
   tests raise the probe plan to 49/49. Two explicitly uninstalled simulator
   prefixes created independent B automatic views and kept A exact, but the
   simulator compositor aborted before the final marker. Complete on iPhone Duo
   or a physical multi-window iPad; do not promote the partial prefix to `PASS`.
12. Completed in `2a15478df`, `dd1b1cf34`, and `EXP-119`: add an exceptional
   explicit Sheet over automatic Home, model its presentation interval, and use
   the complete scene destination for marker source. The corrected run proves
   dedup and eventual H1/S1/H2 restoration, while intentionally failing immediate
   `onDismiss` ownership.
13. Completed in `56969d8a5` and `EXP-120`: exercise direct keyed manual
   start/stop over automatic Home with a step-bounded authority interval. The
   scenario conclusively fails because automatic fallback preempts M1. Adversarial
   fixtures prevent retained H1, pre-M1 duplicates, wrong M1 ownership, H1 reuse,
   or immediate/settled mismatch from passing. The probe plan passes 65/65.
14. Completed in `29c8cec2c`, `b1a0fb6b8`, `a40e7903c`, `EXP-121`, and
   `EXP-122`: switch only the experiment to the internal exact-scene manual path.
   The first run kept M1 authoritative but revealed a staged generic fallback.
   The second rejects that structural candidate, retains Home, and passes 16/16
   with exact backend H1/M1/H2 ownership. The probe plan remains 65/65.
15. Presentation coverage completed in `f452e9e3f`, `fad83f58f`, `c70920c94`,
   and `EXP-123` through `EXP-126`: drive the complete semantic destination
   through exact-scene start and stop while a mounted suppression-only boundary
   excludes its automatic presentation host. Separate semantic authority from
   the outgoing aggregate's delivery lifetime. Independent clean Sheet and
   full-screen-cover runs each pass 14/14 locally and in backend intake with
   H1/M1/fresh-H2 ownership, no automatic presentation duplicate, and zero errors
   or crashes. At that checkpoint the probe plan passed 69/69.
16. Sibling-container coverage completed in `45ec5656a` and `EXP-127`: mount two
   independent `NavigationStack` branches below one outer SwiftUI host, prove
   their exact controller ancestries, keep left M1 authoritative while right
   Detail stages, and reveal only a fresh right Detail after exact stop. The first
   run retained a late probe-only ancestry-reader view as negative harness
   evidence. Exact type filtering plus a mandatory assertion wait produced two
   clean 19/19 runs. The final backend session has four views, 11 actions, 11
   Resources, three long tasks, one session, one vital, and no error or crash.
   The probe plan passes 76/76.
17. Nested manual-stack coverage completed in `EXP-128`: use real Compose and
   Preview SwiftUI destinations with exact-scene keyed starts/stops, require fresh
   Compose and Home occurrences on reveal, and bound duplicate-start misuse with
   a no-view-start interval. Attempt A timed out after C1 was already recorded;
   the driver now treats an earlier exact immutable RUM occurrence like an earlier
   assertion. Clean attempt B passes 29/29, and backend intake confirms distinct
   H1/C1/P1/C2/H2,
   duplicate work on C2, final return work on H2, and no error or crash. The probe
   plan passes 83/83.
18. Same-key A/B contract completed locally in `EXP-129`: use exact scene-context
   markers, start the same `compose` key in both scenes, stop B before A, and
   require independent Compose and returned-Home owners. Six adversarial fixtures
   reject identity and attribution leaks; the full probe plan passes 91/91. The
   clean simulator prefix reached both native scenes but expired before manual
   starts, so runtime acceptance remains in the physical-device queue.
19. Operation/navigation coverage completed in `5d536e0bd` and `EXP-130`: a
   single named scenario drives success H1→D1, failure H2→D2, and duplicate
   `[start H3, start D3, end D3]`. Its local 27/27 result and 93/93 full plan are
   backend-confirmed by seven raw steps and three reduced Operations. The earlier
   H3 start has no synthetic end and the exact corrected warning is preserved.
20. Cross-scene Operation coverage prepared in `a653e29f2` and `EXP-131`: start
   success/failure in A and complete them in B, then start same-name Operations
   with distinct keys in A and B and complete B before A. The 100/100 hostless
   plan rejects shared A/B view identity, wrong-scene B work, B completion on A,
   and A owner drift. Runtime/backend acceptance remains hardware-gated.
21. Open, with the failure mode reproduced in `EXP-117`: add one reproducible run
   command that preflights capabilities, records source revision and binary
   identity, performs explicit host-side uninstall for clean mode or preserves
   state for restoration mode, waits for readiness, and bundles scrubbed manifest,
   capabilities, console, JSONL, semantic result, visual artifacts, and the run-ID
   backend query. The in-app `--probe-run-mode clean` value is not teardown.
   Reject a run if semantic view documents retain another run ID. Unsupported
   resize/topology is `SKIPPED`; credentials never enter artifacts.

The deterministic stack, split, UIKit-transition, exact scene lifecycle,
coexistence, and Operation harness is implemented through `EXP-131`:
three clean
one-window Home → Detail → Home runs produced the same 7/7 semantic `PASS`, and
clean abort and replacement reruns passed 5/5, 6/6, and 6/6. Split replacement
and retained return pass 10/10 and 13/13, while the identically driven automatic
split baseline fails 0/9 for missing semantic views. UIKit cancel/finish pass
11/11 and 13/13 without a Primary RUM view; exact B close with continuing A work
passes 9/9. Exact activation is prepared and fail-closed but still lacks a
qualifying hardware run. The automatic-plus-explicit coexistence run passes 7/7
with no duplicate view locally or in backend intake. The deliberately wrong-view fixture
continues to fail locally with an actionable reason.
The probe-only once-per-container wrapper also passes return, abort, and
same-type replacement with isolated backend evidence. The new scene-selective
coexistence oracle passes its focused tests; two clean simulator prefixes prove
A authority does not suppress B discovery, while terminal B attribution remains
hardware-inconclusive. Two non-uninstalled
back-to-back launches remain local-only and document the host-runner isolation
requirement rather than SDK semantics.
The Sheet and direct-keyed-manual baselines preserve two separate conclusive
failures: immediate legacy Sheet dismissal work remains on S1, while automatic
discovery preempts a legacy direct manual M1. The exact-scene manual successor
passes, and the complete-destination Sheet successor now passes 14/14: semantic
M1 remains authoritative, no automatic Sheet appears, and exact stop reveals one
fresh H2 before immediate and settled work. `EXP-126` independently repeats the
same complete-destination contract for `fullScreenCover`, including target-scoped
dedup through native dismissal and a fresh H2 before both dismiss pairs. The test
plan is 100/100. Presentation-style parity, sibling-container scope, and the
single-scene nested/duplicate manual contract are now closed internally; reviewed
public APIs remain. `EXP-127` adds the exact H1/manual-M1/fresh-Detail sibling
path, with no right-side intermediate view while M1 is current. `EXP-128` adds
H1/Compose-C1/Preview-P1/fresh-Compose-C2/fresh-H2 and confirms that duplicate
Compose misuse creates no restart. `EXP-129` adds the complete same-key A/B and
reverse-stop oracle, but its live simulator attempt expired before manual starts.
`EXP-130` adds backend-confirmed success/failure navigation attribution and
duplicate latest-start semantics without using mapper assertions as Operation
evidence. `EXP-131` adds the exact A-to-B success/failure and distinct-key
reverse-completion contract; its local assertions remain invocation evidence,
not Operation telemetry, until raw and reduced backend intake is captured.
Both same-key and semantic-A/automatic-B acceptance now require capable hardware.
Hardware-only rows remain prepared but unclosed in the experiment rerun queue.

### 1. Stabilize views, navigation, and actions

- Keep the internal, non-serialized scene identifier and scene-keyed
  `RUMViewsHandler` stacks.
- Maintain one active view branch per scene in `RUMSessionScope`; leave unrelated
  branches untouched during navigation and lifecycle changes.
- Retain the passing UIKit and explicit SwiftUI tap, navigation, modal,
  duplicate-identity, and scene-destruction flows as regression gates. Keep the
  focused disconnect/remount tests. `EXP-063` closes handler/state divergence for
  a new platform mount; `EXP-064`/`EXP-065` cover retained-reader re-registration,
  unchanged-attachment deduplication, reconnect cancellation/rearming, cross-scene
  migration, and stale-observer isolation in source and focused tests. `EXP-066`
  passes synthetic retained-reader teardown/remount through runtime, payload, and
  backend intake; genuine OS reconnect/restoration remains open. `EXP-067` now
  puts `NavigationSplitView` and UIKit split/adaptive behavior first. `EXP-068`
  reproduces the regular-width route-owned same-type collapse and wrong marker
  attribution, while `EXP-069` shows automatic mode emits no semantic selection
  views. `EXP-070` restores the exact chain with state-resetting `.id`, isolating
  occurrence identity as the missing input without providing a customer fix.
  `EXP-071` now proves the UIKit mirror manufactures Primary between two
  secondaries. `EXP-073` proves the same false Primary interval on both push and
  pop inside a stable secondary navigation controller, while confirming that the
  reused returned controller already receives a fresh RUM occurrence.
  `EXP-074`/`EXP-075` validate an iOS 27 multi-scene-only atomic same-column
  handoff in both controls: neither backend chain restarts Primary, all markers
  are exact, and the reused returned controller still receives a fresh RUM UUID.
  Those historical runs still start an initial Primary.
  `EXP-077` then hardens unrelated callback, background, and disconnect ordering;
  all 57 handler tests pass. `EXP-079`/`EXP-080` repeat both native controls on
  that revision with the same exact paths. `EXP-082` through `EXP-084` add a
  physical committed pop and deterministic cancel/finish pair without restarting
  Primary during the transition, but retain the initial structural view.
  `EXP-112` adds exact signal-driven transition control and changes the shipping
  iOS 27 multi-scene handler to ignore regular-width structural Primary and
  supplementary columns. Clean cancel/finish runs contain only S1/S2 semantic
  destinations after the native host startup fallback: cancel retains S2 and
  finish creates a fresh returned S1, with exact action/Resource ownership and no
  Primary. The application-subclassed container from `EXP-072`, the native
  SwiftUI host fallback, compact/adaptive behavior, and live ordinary-app
  compatibility remain separate gates. `EXP-086` proves A/B transition overlap,
  but B becoming
  fullscreen stalls A without activation-state evidence; repeat with both windows
  demonstrably visible and able to finish. `EXP-102`/`EXP-103` now pass
  same-type SwiftUI split replacement in one and two windows while preserving
  each retained Detail witness and exact marker ownership. The final `EXP-103`
  hierarchy capture crashed simulator `backboardd` only after telemetry intake,
  so stable simultaneous-visible proof remains routed to hardware. `EXP-072`
  separately proves an
  application-subclassed split container becomes a view, which needs explicit
  predicate-compatibility review. Keep these controls. Preserve one UUID per
  committed path occurrence and exact action/resource attribution to the current
  Secondary destination while closing the remaining container/fallback cases.
  Keep structural lifecycle records in the probe as negative evidence rather than
  deleting them. `EXP-087` proves the new initial-nil/sequence-disable mode creates
  no Detail occurrence. CoreDevice reports that this simulator lacks Resizable
  App Management, so run regular → compact → regular on a capable destination.
  Then finish UIKit scroll/deceleration and per-scene background/foreground.
  Action timeout/stop
  ownership and session rollover already have focused and live coverage.
- Preserve the automatic SwiftUI mode and `EXP-021` as the failing baseline.
  Separate two
  questions in every proposed change: whether the hosting controller resolves to
  the correct scene, and whether it represents the intended customer view early
  enough. The first now passes; the second fails. Add focused coverage for the
  transient root and preceding-view lifecycle attribution before changing the
  tracker. Do not claim success from scene-correct actions alone.
- Keep the standalone native project under
  `Datadog/Example/MultiSceneProbe` as the primary iOS 27 release harness. Its
  single-window baseline proves lifecycle lag without scene competition; its
  `WindowGroup` run proves that lag becomes scene-B-to-scene-A attribution during
  window creation. An automatic-tracking fix must produce `ProbeHomeView` and
  `ProbeDetailView` early enough for all six markers per scene and remove the four
  transient fallback views. The separate explicit-tracking bar requires exact
  lifecycle attribution, no construction-only semantic views, both active scene
  branches, and three clean deterministic runs before expanding the matrix. The
  explicit early-mount candidate meets the exercised part of that bar in
  `EXP-032`, `EXP-033`, and `EXP-038`: three clean runs of the final-gated code
  preserve all 72 lifecycle markers, and five behavior-equivalent A/B runs
  preserve all 120, in addition to the single-window control. Keep automatic mode
  as the P0 baseline; this explicit result does not fix or satisfy its bar.
- Retain the iOS 27-only explicit early-mount candidate while completing its
  construction/visibility matrix. It uses the inherited scene trait when the
  hidden platform reader is created, then falls back to the existing attachment
  and SwiftUI lifecycle signals. It must remain disabled for iOS 15-26, visionOS,
  and ordinary single-scene applications until broader evidence justifies a
  wider scope. `EXP-034` through `EXP-036` pass dormant-destination, three-cycle
  push/pop, and unselected-tab checks. `EXP-039` is inconclusive because
  `ViewThatFits` never constructed its rejected platform child; do not repeat
  that arrangement. Next cover aborted programmatic navigation, immediate scene
  closure with another window demonstrably remaining foreground, split
  navigation, restoration, and a container that actually preloads an offscreen
  subtree. `EXP-041` already proves closing B is crash-safe and preserves B
  ownership through delayed completion, but its fullscreen topology backgrounded
  A and cannot prove visible-peer continuity. `EXP-042` proves a restored B keeps
  its native scene identity and receives a correct new RUM occurrence, but iPadOS
  did not reconnect A; concurrent restoration remains open.
- Keep the modal occurrence control and `EXP-040` as a release regression.
  Presenting and dismissing must emit `Home₁ → Sheet → Home₂`, with distinct Home
  UUIDs and post-dismiss work on Home₂ even when SwiftUI retains the Home value.
- Preserve the navigation-occurrence contract in tests and reviews. A retained
  SwiftUI object returning after a pop starts a new RUM view ID because RUM models
  the user's path, not platform-object lifetime. `Home → Detail → Home` is
  three occurrences, including two distinct Home IDs. Conversely, a cancelled
  interactive transition must not add Home and restart Detail. `EXP-037`
  reproduces that false interval with and without early mount. `EXP-043` proves
  that the retained Home can resolve an initially interactive public UIKit
  coordinator during its speculative callback and that cancellation is known at
  completion. `EXP-044` validates the scene-local completion gate in the native
  probe and backend: cancellation discards all staged lifecycle state, while
  successful completion stops Detail and starts a fresh Home occurrence. Keep
  ordinary pushes, Back-button pops, older systems, and single-scene apps on the
  existing immediate path. `EXP-045` hardens the implementation with state-specific
  observer resolution, matching-scene root fallback for an unattached recreated
  reader, scene-plus-coordinator transaction keys, provisional ownership
  revalidation, unrelated same-scene escape, and cross-scene attachment
  correction. Its 19/19 focused tests are not a runtime substitute. `EXP-086`
  proves overlapping A/B transitions, but fullscreen topology prevents A from
  finishing; repeat with two demonstrably visible and independently active scenes.
  Also retain successful-transition construction-without-attachment and
  disconnect/reconnect of a surviving reader in the container/restoration matrix.
- Treat the public lifecycle-hook search as complete unless new Apple API evidence
  appears. LLDB proves navigation titles become observable only after Home work,
  Detail work precedes both hosting-controller and base UIKit appearance callbacks,
  and the apparent iOS 27 reflection replacement reports a registered destination
  while Home is visible. The existing explicit `.trackRUMView` path now has an
  internal iOS 27 candidate, but transparent automatic tracking still needs a
  reviewed semantic root/navigation integration. `EXP-055` confirms that
  iOS-26+ `UIHostingSceneDelegate` is an application-owned root/lifecycle bridge,
  not a destination-identity hook. `EXP-085` confirms `NavigationStack`,
  `NavigationPath`, and public transition APIs expose no alternative transparent
  semantic destination hook. Do not swizzle SwiftUI internals or ship navigation
  titles as view names.
- Continue automatic semantic tracking from a scene-local, path-aware navigation
  integration rather than adding another discovery hook. `EXP-046` proves the
  typed binding exposes commit and cancellation, while `EXP-047` through
  `EXP-049` reject background-sibling, whole-stack-wrapper, and stable-first-child
  trackers: each remained too late for scene B's initial work, and the wrapper
  replayed retained lifecycle. `EXP-050` passes only after tracking is installed
  directly at the Home and typed-destination builders; `EXP-051` preserves that
  result through a cancelled and then completed pop. The smallest credible
  contract therefore needs one integration at each independent navigation
  container, an explicit root descriptor, the application's existing bound path
  or router, and one centralized resolver for route-to-RUM metadata. It must not
  require a modifier in every destination. `EXP-052` proves path writes alone are
  not the occurrence: a same-turn Detail/Home mutation produced no new RUM view. The SDK
  must combine route state with the content that actually materializes and place
  that view boundary before customer lifecycle work; a passive `onChange` remains
  only an experiment because it has no ordering guarantee.
  Keep route frames distinct from RUM occurrences: pushing starts the destination,
  and popping starts a fresh occurrence for the revealed frame, so
  `Home₁ → Detail → Home₂` remains mandatory. A generic `NavigationPath` exposes
  count/codable mutation but no public last-element iteration, and
  `NavigationLink(destination:)` exposes no authoritative bound path, so those
  cases require an explicit semantic descriptor or destination tracking. This
  customer-facing boundary and its mixing rules with
  `DefaultSwiftUIRUMViewsPredicate` require RFC/API review before production code.
  Automatic discovery remains enabled elsewhere. Within this integration's target
  container, semantic/manual ownership is authoritative and must suppress a
  duplicate automatic view without suppressing unrelated scenes or containers.
  `EXP-054` and `EXP-056` now pass a replacement whose different destination type
  materializes, first in one scene and then independently in A/B. `EXP-057` now
  reproduces the expected same-type/same-name failure: SwiftUI reuses its reader
  and RUM keeps Detail₁ active after Detail₂ commits. `EXP-058` proves a
  probe-only `.id(route)` control creates the required second occurrence. Do not
  ship that as customer guidance because it resets customer SwiftUI state. Design
  a token that restarts only RUM occurrence state, validate it concurrently, then
  exercise restoration and split navigation. `EXP-052` closes only the coalesced
  same-turn abort.
  Record where a binding mutation does not become a semantic occurrence. Validate
  occurrences from distinct RUM UUIDs and stop/start order, not from a copied path
  counter: retained Home kept a stale diagnostic attribute in `EXP-051` while
  correctly receiving a new view UUID.
- Keep the rejected iOS 27 `viewIsAppearing` experiment `EXP-023` in the ledger.
  The callback
  remained later than customer `.onAppear`/immediate `.task`, did not remove the
  transient root, and added a base-controller swizzle. Its implementation was
  removed; do not restore it without different runtime evidence.
- Preserve the legacy no-scene and single-scene paths without meaningful hot-path
  overhead.
- Gate the hidden SwiftUI scene reader and UI-event-only causal instrumentation
  behind the configured bundle's explicit multi-scene declaration. Normal apps
  retain the original direct modifier and do not activate the extra causal
  handoff, while scene-aware UIKit command routing remains internal. Validate the
  total single-scene path live before calling it behaviorally identical.
- On iOS 17+, retain the internal `UITraitDefinition` bridged by
  `UITraitBridgedEnvironmentKey` and seeded from each real `UIWindowScene` while
  its full matrix remains stable. The iOS 27 probe proves this supplies earlier
  scene identity and materially reduces the attachment race, but not that an
  inner modifier runs before customer outer lifecycle callbacks. Keep the hidden
  reader as a late-start/fallback path and availability-gate the trait mechanism
  so the SDK remains compatible with its iOS 15 deployment target. Do not build a
  separate pre-iOS-27 semantic integration or infer a scene from global/window
  ordering. Validate the supported behavior on iOS 27/27.1; earlier semantic
  support is a bonus only when it comes from the same uncompromised path.

#### SwiftUI route-occurrence token design gate

`EXP-057`/`EXP-058` isolate the next implementation boundary. Keep one stable
`RUMViewTrackingState` and hidden reader, but let a reviewed explicit occurrence
key rotate Datadog's internal generation when SwiftUI updates the same materialized
destination in place. The key is local control data: never serialize or log it,
and never use it as the backend RUM view UUID. The existing `.trackRUMView`
overload retains compatibility behavior and derives new occurrences only from the
lifecycle callbacks SwiftUI exposes; it must not be described as defining RUM
views by platform lifetime. `EXP-060` completes the internal atomic handler
primitive and its focused stack/scene tests. `EXP-061` prevents a prior inactive
occurrence from absorbing a later start/stop that reuses its platform identity,
including across sessions, and establishes restored scopes' synthetic start
boundary so same-identity restart leaves one active occurrence.
`EXP-062` completes the dormant internal state/arbiter propagation: keyed
occurrences use fresh command identities, same-scene changes call the atomic
replacement primitive, scene changes use stop/start, stale generations fail
closed, and interactive candidates reduce to the final committed value. The
existing public modifier still uses the legacy configuration. `EXP-063` now
silently invalidates A-owned state when the handler tears down scene A, preserves
B, and requires an authorized platform remount before any occurrence can restart.
`EXP-064` wires the retained reader back into the arbiter; `EXP-065` hardens that
path after review found authorization loss, duplicate ordinary mounts, stale-trait
resurrection, cross-scene observer contamination, destination migration loss, and
cancelled-remount fencing. `EXP-066` passes the integration under synthetic
disconnect injection without replacing the still-live scene or reader.
`EXP-077` hardens the passing `EXP-074`/`EXP-075` UIKit candidate after review;
`EXP-079`/`EXP-080` repeat nested push/pop and stock replacement without bundling
`EXP-072`'s predicate change. `EXP-082` through `EXP-084` close committed and
cancelled nested-transition controls; `EXP-086`/`EXP-087` leave simultaneous
visibility and capable-destination adaptive resize open. `EXP-090` then proves
same-type keyed replacement can preserve customer state, and `EXP-091` preserves
the unmaterialized-abort rule. `EXP-092` through `EXP-097` isolate retained Home's
return ordering and detached reader. `EXP-098`/`EXP-099` pass the debug per-window
occurrence source through runtime and backend: Home₂ starts before immediate
post-pop work without replacing customer state. `EXP-100` leaves recognized native
gesture validation open because both synthetic drags were ignored. `EXP-102` and
  `EXP-103` then extend the same occurrence input to `NavigationSplitView`: one and
two windows each keep a retained Detail witness while Detail₁, Detail₂, and
  Placeholder receive distinct exact RUM occurrences without customer `.id`.
  `EXP-104` catches the returned-route remount duplicate, and `EXP-105` fixes it by
  transferring the source-published occurrence to the replacement tracking state.
  Adaptive collapse/expand on capable hardware remains next. The broader next step remains a
reviewable iOS 27 integration design, not another lifecycle-discovery hook;
genuine OS reconnect/restoration remains a separate lifecycle gate.

The implementation must satisfy these constraints:

- `updateUIView` reports occurrence configuration and current attachment together,
  even when attachment has not changed. It rebinds and re-registers its observer
  idempotently; the committed state owns semantic deduplication and the observer
  suppresses unchanged ordinary attachment notifications. This source path is now
  covered by `EXP-064`/`EXP-065`. `EXP-090` proves keyed configuration delivery at
  runtime without resetting customer state; a supported customer-facing entry
  point remains behind the API gate.
- A new key while appeared and attached creates a fresh internal identity and new
  descriptor without replacing customer content or `@State`.
- Do not express this as ordinary stop then start calls through
  `RUMViewsHandler`. Removing the active stack item intentionally restarts the
  underlying Home entry. Retain the internal same-stack replacement primitive that
  stops the old occurrence, replaces that exact slot, and starts the new one
  atomically, so `Detail₁ → Detail₂` cannot synthesize Home. `EXP-060` passes all
  43 handler tests for visible, covered, inactive, missing, cross-scene, and
  same-name cases.
- Replacement below another visible item updates only the covered slot. Combined
  occurrence and scene migration stops the old identity in A and starts the fresh
  identity in B. An arbitrary detached configuration still cannot guess a scene.
  The narrower retained-route reveal may use the reader's last concrete scene only
  after that occurrence previously started there; disconnect clears the proof and
  requires a newer concrete mount.
- The interactive arbiter retains the final candidate key and descriptor alongside
  attachment/appearance. Success commits one replacement; cancellation changes
  neither key, identity, descriptor, nor handler stack. Multiple candidates reduce
  to the final one, and scene disconnect discards them. The internal state and
  exact deferred-transaction checks now satisfy this in `EXP-062`; the committed
  occurrence owns an immutable descriptor, and its publisher regression rejects a
  stale modifier fallback. Reader-delivered keyed occurrence configuration is now
  exercised by `EXP-090`; `EXP-098`/`EXP-099` add the early retained-route source.
  Both remain debug integration evidence pending reviewed API and mixing rules.
- Tag lifecycle work by generation so a late disappear from Detail₁ cannot stop
  Detail₂. Keep the same state object across generations because deferred arbiter
  membership uses its object identity.
- Never infer an occurrence from name, generated path, attributes, or the outer
  modifier's random identity. Those values can change without navigation, while
  two real occurrences may intentionally share all descriptors.

The preferred RFC direction is now an iOS-27-gated container modifier equivalent
to `trackRUMNavigation(path:root:destination:)`. It consumes the customer's
existing path/router once per independent `NavigationStack`, resolves route
metadata centrally, and rotates only internal RUM occurrence identity when a
committed route appears or reappears. The exact generic/path erasure, overloads,
and availability require API review. Existing `.trackRUMView` remains valid for
individual exceptions; an explicit/manual target is authoritative only in its
container and cannot produce a duplicate automatic view.

`EXP-116` validates the implementable probe shape. A wrapper owns the
`NavigationStack` root and typed destination builder, takes one path binding plus
one resolver, and injects the existing early route-owned tracker only where the
root or a committed destination materializes. Customer Home/Detail view types no
longer contain RUM metadata. Return creates H₂, same-turn push/revert creates no
Detail, and an in-place same-type replacement creates a fresh same-named Detail₂
without resetting customer content identity. This does not require the final
public API to be a wrapper, but it does require equivalent access to the
materialized destination boundary; the passive root/background approaches in
`EXP-047` through `EXP-049` remain known-too-late.

The first authority mechanism is implemented internally in `4fc9d91b3`. A weak
registry associates each explicit modifier's hidden observer with its lifecycle
state. Automatic SwiftUI controller discovery is skipped only when an appeared,
window-attached observer is contained by that controller; detached/inactive
entries and unrelated sibling controllers remain eligible, and UIKit predicate
acceptance keeps precedence. `EXP-115` proves exact H1/D1/H2 output with both
tracking modes enabled. `EXP-116` completes the once-per-container path/resolver
prototype, and `EXP-118` proves from two simulator prefixes that semantic A does
not globally suppress automatic B. `EXP-127` then proves the registry remains
container-local across two sibling controller branches below one outer SwiftUI
host: left manual authority does not make the right branch ineligible, and only
the latest committed right destination is revealed. The ancestry assertion is a
required capability witness; without it the run is `INCONCLUSIVE`. Still required
are the terminal B marker on physical hardware and reviewed public ownership of
the proven boundary. The immediate exceptional-view return defect exposed by
`EXP-119` is superseded internally by `EXP-125`/`EXP-126`.

Focused validation covers mounted replacement, unchanged key, returning to an
earlier key with a fresh third UUID, detached change, simultaneous scene migration,
stale old-generation disappear, descriptor change with the same key, legacy
compatibility behavior, atomic top/covered stack-slot
replacement, same-name identities, A/B isolation, successful/cancelled interactive
replacement, multiple candidate keys, disconnect invalidation/remount, and
concurrent coordinators. Retained-reader update/re-registration, unchanged
attachment deduplication, disconnect rearming, and success/cancellation behavior
are focused-test covered. `EXP-066` provides a synthetic reconnect pass;
`EXP-090`/`EXP-091` pass same-type replacement and abort without customer-content
identity changes; `EXP-098`/`EXP-099` pass retained Home return and immediate work.
`EXP-102`/`EXP-103` pass same-type split replacement in one and two windows;
`EXP-105` passes return to a retained split selection across a SwiftUI reader
remount. Genuine OS reconnect/restoration, adaptive navigation, and a recognized
native interactive gesture remain open. Shipping acceptance still
requires the same behavior through a reviewed iOS 27 integration, plus
simultaneous-visible A/B and adaptive split validation.

The internal state and arbiter checkpoints pass 35/35 and 38/38, with two targeted
handler tests. The retained-route source passes 17/17 focused cases. This
includes keyed A/B
cancellation-versus-commit isolation, exact publisher scene targets, silent
disconnect invalidation, N-to-N+1 remount fencing, peer-scene preservation,
source-A disconnect during a pending migration to B, cancellation rearming,
reader-mount/disappear ordering, stale A-observer isolation from B's coordinator,
ordinary detach, explicit unresolved attachment rejection, stale/duplicate source
generation, and same-key A/B source isolation. Mixing with the existing automatic
tracker is now internally and backend validated for one active subtree in
`EXP-115`; `EXP-116` adds one centralized path/resolver call site with exact
return, abort, and same-type replacement evidence. The supported entry point and
broader container matrix remain behind reviewed integration. Do not convert the
passing debug path into a customer-support claim.

This phase is implemented experimentally and has the strongest unit, simulator,
and backend evidence. It remains the primary workstream independent of the
Resource/Trace investigation.

### 2. Review scene-aware manual views and the explicit Operation target

Scene-aware manual view targeting is required, independently of Operations. Add
reviewed Swift and Objective-C start/stop forms that accept a `UIWindowScene`
without exposing internal UUIDs. The same customer key must coexist in A and B;
stopping A closes only A. Existing forms remain source-compatible and keep their
inferred/last-interacted behavior, while automatic tracking continues outside an
explicitly targeted exceptional view. The concrete proposal and compatibility
options live in [NAVIGATION_API.md](NAVIGATION_API.md).

Routing the existing start/stop commands to `.scene` is necessary but not
sufficient. Direct monitor calls bypass `RUMViewsHandler`'s retained platform-view
stack, so stopping an exceptional manual view can leave no underlying automatic
occurrence to reveal, and a later automatic appearance can immediately replace
the direct manual scope. `EXP-120` confirms both consequences: Compose M1 stopped
31–48 ms after start, the automatic fallback owned its decisive work, and only a
later H2 received settled work. Require automatic Home H1 -> manual M1 -> fresh
automatic Home H2 in one scene while a peer scene remains unchanged.

The internal slice is complete in `29c8cec2c` and `b1a0fb6b8`. `Monitor` is weakly
bound to the handler-owned scene-targeted capability; exact start inserts
`.manual` into the scene stack, the active manual suffix remains authoritative,
trustworthy automatic destinations are staged beneath it, and exact removal
applies stop attributes and reveals a fresh occurrence. Known generic SwiftUI
hosting fallbacks are rejected during this authority interval while the last
semantic destination is retained. Existing source-less methods remain direct and
inferred. Focused tests cover H1/M1/H2 order, automatic replacement, nested
manuals, same key in A/B, wrong-scene stop, stop attributes, disconnect, and a
fresh restarted UUID. `EXP-121` isolates generic-fallback reveal after authority
was fixed; `EXP-122` then passes 16/16 locally and in backend intake. Commit
`f452e9e3f` closes the approved internal edge cases: several underlying commits
emit no intermediate view and reveal only the latest; a nested Preview stop
starts a fresh Compose occurrence; and duplicate active `(scene, key)` starts are
ignored crash-safely without restart/reference-counting. Legacy source-less stop
remains a separate inferred API, not a supported pair for targeted start. Take
the surface through API review, then obtain live same-key A/B proof on capable
hardware. `EXP-128` now provides the independent runtime proof for the nested
Preview and duplicate-active-key portions, including fresh C2/H2 IDs and exact
action/Resource owners.

`EXP-119` is the legacy modifier-based presentation baseline: it eventually
restores H2 without a duplicate, but immediate `onDismiss` work still owns S1.
`EXP-123` proves exact handler authority alone still permits a redundant automatic
presentation host. The suppression-only subtree boundary in `f452e9e3f` and the
corrected interval oracle in `fad83f58f` close the Sheet path: `EXP-125` has exact
H1/M1/fresh-H2 ownership before immediate work and no automatic Sheet. The
presentation replaces the scene's current RUM destination. Commit `c70920c94`
adds an independent full-screen-cover discriminator, and `EXP-126` passes the
same 14/14 contract with no automatic cover and exact H1/M1/fresh-H2 ownership.
`EXP-127` closes the internal sibling-container discriminator with two distinct
controller ancestries and exact H1/M1/fresh-Detail ownership. The public router
integration still requires API review. `EXP-128` closes the live
nested-manual/duplicate-active-key sequence. `EXP-129` closes the hostless
same-key exact-scene contract and routes its live acceptance to capable hardware
after the simulator session expired before manual authority began.

`EXP-130` closes the available single-scene Operation/navigation experiment. It
proves that every step resolves its call-site destination independently, that a
failure preserves its reason and end owner, and that a duplicate start changes
only the locally tracked latest instance. It deliberately records local API
invocation assertions rather than counterfeit Operation mapper evidence; raw and
reduced backend documents are the attribution oracle. The remaining Operation
work is exact A-to-B/reverse completion on capable hardware and public targeting
API review.

The explicit Operation view-target escape hatch is also part of the support goal.
Use the [Operations contract and API proposal](OPERATIONS.md) as the review starting
point, retain the existing APIs and their inferred behavior, and do not expose
internal RUM view UUIDs. Resolve UIKit objects synchronously into internal
scene/logical-view targets and provide an Objective-C companion. Add the same
parameter to any future public update/retry API. Implementation remains blocked
on normal public API review, not on further source-discovery experiments.

The internal scene target used by both APIs should have a natural optional slot
for the future Window Execution Context identity. It must not serialize a temporary
window attribute, split the RUM session, or make current fixes wait for backend
Execution Context presentation.

### 3. Reduce Resource/Trace work to a bounded provenance experiment

- Keep `UIApplication.sendEvent` only as a short dynamic scope around the actual
  event dispatch. Re-read the swizzling safety rules before retaining any change
  and measure per-event overhead and recursion behavior.
- Carry an opaque scene token synchronously and through structured `TaskLocal`
  inheritance. Never use a thread identifier as async ownership.
- Resolve fresh scene context at actual request/span start, then freeze one owner
  through completion. RUM and Trace must share that same start selection.
- Retain `EXP-088`: public manual action calls and all manual Resource starts use
  an available execution-local exact view, then its scene, before falling back to
  the representative. Resource metrics/stops/errors stay key-owner routed so a
  completion in B cannot abandon a Resource started in A. `EXP-089` proves the
  physical filtered-control path, backend capture, owner completion, and later
  last-interacted fallback, but fullscreen A activation had already made A
  representative. Repeat with both windows simultaneously visible to prove exact
  precedence over a different representative.
- Treat custom handlers that later rewrite an eligible request across
  first-party or disallow boundaries as developer misuse, outside this project.
  Do not add final-request header rollback, GraphQL reconstruction, or a generic
  handler-finalization contract for that case.
- Do not retain synchronous resource pre-start, third-party handler callbacks,
  context maps, or private thread keys merely because they improve unsupported
  cases. Each mechanism needs a failing experiment, a focused regression, and a
  compatibility reason.
- Keep the pending-action merge only if it cannot revive another scene from an
  intentional nil, capture the previous action, depend on queue timing, or create
  an action ID that never receives a RUM action event. Intentional nil is now
  covered for both Logs and Trace. The live URLSession runs prove accepted versus
  filtered actions and the 20/200 ms action-validity boundary; the earlier
  overlapping-action run and its fixed rerun prove new actions no longer fan out.
  `EXP-088` closes the synchronous filtered-interaction case in source/focused
  tests because manual calls made during dispatch now consume its scene handoff.
  `EXP-089` physically rejects the automatic action and confirms that a later GCD
  call uses last-interacted A. It does not compare the synchronous call against a
  different representative because switching windows first created a new A view.
  Do not persist scene ownership beyond the causal boundary.

The current `RUMContextHandoff`, thread-dictionary bridge, synchronous Resource
pre-start, captured owner maps, and altered third-party-handler callback path remain
experimental. `EXP-088` validates Monitor consumption in source and focused tests;
`EXP-089` validates live dispatch but leaves the differing-representative
discriminator open. No additional Resource/Trace routing should be layered on
this path until the remaining live matrix proves which pieces are necessary.

### 4. Fix core owner routing independently of source discovery

- Resolve one `.view` destination once before mutating view scopes. A completion
  must not first remove its old resource owner and then fall through to the
  current view in the same propagation pass.
- Distinguish cached ownership as scene-backed, known legacy, or genuinely
  unknown. Preserve historical fallback for known legacy work while failing
  closed for unknown work beside concurrent scene-backed views.
- Pin live cache entries, retain inactive ownership for a bounded TTL, and keep
  eviction fair across scenes.
- For feature operations, resolve each step from its own trustworthy call-site
  target. Refresh a lightweight last-proven view snapshot whenever that target
  resolves, and use it only when a later step has no better context. Keep the
  snapshot separate from stopped view scopes, strip view attributes, and never
  use it to update or resurrect an old view.
- Keep exact `(name, operationKey)` identity application-wide and independent of
  scene. Parallel instances with the same name require unique keys. On duplicate
  starts, track only the latest locally, emit no synthetic end, and warn that the
  earlier backend operation remains open until its four-hour timeout.
- Use the same typed tuple for Profiling correlation. Do not derive a dictionary
  identity by joining customer-controlled strings with a delimiter.

These rules improve correctness after an owner is already known and do not claim
that the SDK can discover a scene for arbitrary work.

Source-less work otherwise retains the process representative for compatibility.
Keep these broader contracts as future options only if customer evidence later
justifies deterministic attribution:

- A fast, thread-safe request-start Resource context resolver receiving the
  `URLRequest`, any automatic origin, and all active candidates. Each candidate
  would contain an opaque scene/session identity, view ID/name/path, relevant
  view context, and a valid current action. It would return one candidate or nil
  for shared/unknown work. Product review must decide whether this is fallback-only
  or may override automatic provenance, and it must not overload the existing
  completion-time `resourceAttributesProvider` contract.
- A general scoped RUM-context API for manual spans, logs, and other work. A
  Resource-only resolver cannot make those surfaces deterministic.

The broader resolver/context APIs require RFC/product review before implementation.
Do not spend this project on a pre-iOS-27 semantic escape hatch or add either
speculatively. Neither can invent causality when request metadata and application
context do not distinguish a scene.

### 5. Validate, simplify, and regress

- Extend the probe before running cases for which no control currently exists:
  restoration, WebView, fatal/exported context, and mirrored logger errors.
  Stack, SwiftUI split, and UIKit split navigation already have signal-driven
  controls and must use those existing scenarios.
- Finish only the untested causal-boundary rows: SwiftUI Button -> structured
  `Task`, shared/coalesced work, two-scene reverse completion, and trace-only
  URLSession. Do not repeat structured-task inheritance, source-less schedulers,
  lifecycle fallback, trace teardown, accepted/rejected action, action expiry, or
  operation teardown unless a later change can affect them.
- Repeat the `EXP-089` filtered UIKit event with A/B simultaneously visible. Keep
  B representative, tap A without triggering A appearance, and invoke at least
  one synchronous Resource start before any exact action can update the
  representative. That Resource and the manual action must select exact A; after
  the interaction, delayed source-less work must use last-interacted A. Fullscreen
  switching is invalid because it creates a fresh A occurrence before the tap.
- Run the new cross-window Operation controls independently of the Resource/Trace
  matrix: start in A then succeed in B, start in A then fail in B, and duplicate
  the same identity before ending it. Capture console warnings, raw vital view IDs,
  and reduced start/end views. Repeat parallel distinct keys in reverse order only
  if focused coverage or the simpler runtime cases reveal disagreement.
- Before using the fixed “Other Window” control with more than two sessions,
  select a target explicitly or verify the logged target: the current helper takes
  the first other member of an unordered `openSessions` set. Relaunch or reset the
  one-shot shared-request state before repeating that experiment.
- Remove speculative machinery that does not move a supported case from wrong to
  correct.
- Rerun complete RUM, Internal, Logs, Trace, and WebView suites, plus legacy
  single-window integration flows and URLSession custom-handler behavior.
- Treat Session Replay as crash-safety coexistence only.
- Update the [assessment](ASSESSMENT.md) and
  [canonical overview](../MULTI_SCENE_SUPPORT.md) with exact supported, partial,
  ambiguous, and unsupported surfaces before proposing a release contract.

## Completion gates

The assessment can change to supported only when:

- concurrent UIKit and SwiftUI windows keep independent view lifetimes and never
  attribute a new scene's work to another scene. Automatic SwiftUI remains the
  zero-code default; the optional reviewed container integration provides exact
  root/destination occurrence semantics in both native `WindowGroup` and
  UIKit-hosted applications;
- stack, modal, split/adaptive, and restored navigation plus tap and scroll actions
  are attributed to their originating windows; same-type split replacement and
  retained split return now pass experimentally, while adaptive hardware remains
  open;
- each scene has exactly one current RUM destination: structural Primary/sidebar,
  split container, and tab-bar surfaces never create competing views. The stock
  regular-width UIKit path passes after `EXP-112`; the application-subclassed
  container, native-host startup fallback, compact/adaptive transitions, and tab
  modeling remain open;
- `Home → Detail → Home` produces distinct H1/D1/H2 occurrences, and the optional
  semantic integration consumes an existing router's complete destination through
  one centralized resolver, including sheets and full-screen covers, coexists
  with automatic tracking, and suppresses duplicate automatic views only within
  its authoritative container;
- the iOS 27 explicit early-mount result survives the remaining aborted,
  split, restoration, stable visible-peer close, and preloaded-container stress;
  modal navigation and closing-scene ownership already pass. Its three successful
  final-code A/B runs are strong evidence, not a documented SwiftUI callback-order
  contract;
- cancelled interactive SwiftUI navigation does not create a RUM occurrence for
  a path the user never completed, while completed pop/push continues to create
  one new occurrence per path transition; focused recreated-view and unrelated
  same-scene isolation pass, but a recognized human-driven native cancellation
  and completion plus simultaneous A/B transitions still need live proof; ignored
  synthetic drags do not satisfy this gate;
- bounded Resource/Trace provenance is validated with actual URLSession timing,
  while unknown-provenance work is explicitly classified and follows the approved
  process-representative fallback;
- RUM Resource and Trace freeze and share one request-start selection whenever a
  trustworthy owner exists, including navigation, rollover, reverse completion,
  and scene closure; manual actions and Resource starts invoked within the
  execution-local UI-event handoff use its exact view/scene, while later
  source-less calls retain representative compatibility;
- Operations expose correct per-step start/end views across windows, preserve
  last-proven context only as fallback, keep exact application-wide
  `(name, operationKey)` identity, and provide the reviewed explicit target API;
- reviewed scene-aware manual view APIs let the same key coexist in A and B and
  stop only the targeted scene, have Objective-C counterparts, preserve existing
  inferred APIs, pair targeted start only with targeted stop, and coexist with
  automatic tracking elsewhere. Underlying navigation emits no intermediate view
  while a manual suffix is authoritative and reveals only the latest committed
  destination as a fresh occurrence; nested distinct keys return as fresh manual
  occurrences; duplicate active keys remain crash-safe misuse;
- manual errors, logs and mirrored errors, WebView containers, feature flags,
  INV/TNS/vitals, fatal/exported context, profiling, and process-wide long
  tasks/hangs have explicit support levels and targeted runtime evidence or an
  explicit process-representative limitation; Session Replay coexists without a
  crash even though scene-correct replay is not claimed;
- background, foreground, destruction, disconnect, reconnect, and restoration do
  not disturb unrelated windows;
- tests cover duplicate identities, disconnect, restoration, session expiration,
  and foreground/background transitions;
- single-scene and legacy lifecycle tests plus a live ordinary-app flow demonstrate
  no regression; the extra `UIApplication.sendEvent` path has measured acceptable
  overhead and passes recursion/reentrancy stress with and without action tracking;
- raw intake and the local reducer agree on ownership and occurrence order inside
  one application session. Internal scene identity is stable and ready to map to
  a future Window Execution Context ID without any temporary serialized window
  concept; backend Execution Context visualization is not a release blocker;
- the iPad probe and backend session both confirm the intended model, followed by
  iPhone Duo validation on iOS 27.1 when that runtime is available.
