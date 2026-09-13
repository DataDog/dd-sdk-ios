# RUM multi-scene implementation and validation plan

Read this document when choosing or executing the next implementation slice,
extending the probes, or checking the release gates. Evidence and current support
levels live in [ASSESSMENT.md](ASSESSMENT.md); chronological run details live in
[EXPERIMENTS.md](EXPERIMENTS.md). Start at the
[canonical overview](../MULTI_SCENE_SUPPORT.md) for the current resume point.

Evidence references use the stable `EXP-*` identifiers from the experiment
ledger; exact run and session identifiers remain in `EXPERIMENTS.md`.

Last updated: 2026-09-13

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

1. Convert the debug per-window keyed-occurrence source into a reviewable iOS 27
   SwiftUI integration contract; no public API lands without RFC review.
2. Obtain a recognized native SwiftUI interactive cancel/finish run on physical
   hardware or with human input.
3. Preserve the passing same-type `NavigationSplitView` occurrence source from
   `EXP-102`/`EXP-103`, then validate returning to a previously selected retained
   detail and adaptive collapse/expand without customer `.id` or state reset.
4. Validate simultaneous visible A/B transitions, then genuine disconnect,
   restoration, and adaptive topology on capable hardware.
5. Complete Operation public targeting and its live backend matrix.
6. Close the bounded causal/downstream rows and live normal-app compatibility.

The UIKit split and exact-owner fixes remain regression gates, but they no longer
precede the automatic SwiftUI P0. Device-limited rows are routed through the
real-device/human queue instead of repeated on the current simulator.

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
  `EXP-077` then hardens unrelated callback, background, and disconnect ordering;
  all 57 handler tests pass. `EXP-079`/`EXP-080` repeat both native controls on
  that revision with the same exact paths. `EXP-082` through `EXP-084` add a
  physical committed pop and deterministic cancel/finish pair without false
  Primary occurrences. `EXP-086` proves A/B transition overlap, but B becoming
  fullscreen stalls A without activation-state evidence; repeat with both windows
  demonstrably visible and able to finish. `EXP-102`/`EXP-103` now pass
  same-type SwiftUI split replacement in one and two windows while preserving
  each retained Detail witness and exact marker ownership. The final `EXP-103`
  hierarchy capture crashed simulator `backboardd` only after telemetry intake,
  so stable simultaneous-visible proof remains routed to hardware. `EXP-072`
  separately proves an
  application-subclassed split container becomes a view, which needs explicit
  predicate-compatibility review. Keep these controls. Verify one UUID per
  committed path occurrence, no
  callback-manufactured Primary/Sidebar interval, and exact action/resource
  attribution. `EXP-087` proves the new initial-nil/sequence-disable mode creates
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
  contract therefore needs an explicit root descriptor, an authoritative typed
  `[Route]` path, and a customer resolver or SDK-owned builder wrapper for every
  route's RUM descriptor. `EXP-052` proves the path writes alone are not the
  occurrence: a same-turn Detail/Home mutation produced no new RUM view. The SDK
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
Placeholder receive distinct exact RUM occurrences without customer `.id`. The
next split row is returning to a previously selected retained detail, followed by
adaptive collapse/expand on capable hardware. The broader next step remains a
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

The preferred RFC-only additive shape is an iOS-27-gated overload equivalent to
`trackRUMView(name:occurrenceKey:attributes:in:)` with a generic `Hashable` key,
erased immediately inside the SDK. Do not replace the existing symbol or add a
defaulted optional parameter. The key is modifier-local, stable for one materialized
route value, and changed only for a committed occurrence. Navigation-specific
destination wrappers remain a broader alternative, not the first implementation.

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
`EXP-102`/`EXP-103` pass same-type split replacement in one and two windows.
Returning to a retained split selection, genuine OS reconnect/restoration, and a
recognized native interactive gesture remain open. Shipping acceptance still
requires the same behavior through a reviewed iOS 27 integration, plus
simultaneous-visible A/B and adaptive split validation.

The internal state and arbiter checkpoints pass 34/34 and 38/38, with two targeted
handler tests. The later retained-route source passes 13/13 focused cases. This
includes keyed A/B
cancellation-versus-commit isolation, exact publisher scene targets, silent
disconnect invalidation, N-to-N+1 remount fencing, peer-scene preservation,
source-A disconnect during a pending migration to B, cancellation rearming,
reader-mount/disappear ordering, stale A-observer isolation from B's coordinator,
ordinary detach, explicit unresolved attachment rejection, stale/duplicate source
generation, and same-key A/B source isolation. Mixing with the existing automatic
tracker and the supported entry point remain behind reviewed integration. Do not
convert the passing debug path into a customer-support claim.

This phase is implemented experimentally and has the strongest unit, simulator,
and backend evidence. It remains the primary workstream independent of the
Resource/Trace investigation.

### 2. Reduce Resource/Trace work to a bounded provenance experiment

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

### 3. Fix core owner routing independently of source discovery

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

### 4. Review the explicit Operation target; defer generic attribution APIs

The explicit Operation view-target escape hatch is part of the support goal. Use
the [Operations contract and API proposal](OPERATIONS.md) as the review starting
point, retain the existing APIs and their inferred behavior, and do not expose
internal RUM view UUIDs. Resolve UIKit
objects synchronously into internal scene/logical-view targets and provide an
Objective-C companion. Add the same parameter to any future public update/retry
API. Implementation remains blocked on normal public API review, not on further
source-discovery experiments.

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
  split navigation, restoration, WebView,
  fatal/exported context, and mirrored logger errors.
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

- concurrent UIKit and explicit SwiftUI windows keep independent, correct view
  lifetimes, and automatically tracked SwiftUI creates the semantic root and
  destination before lifecycle work is attributed, in both native `WindowGroup`
  and UIKit-hosted applications;
- stack, modal, split/adaptive, and restored navigation plus tap and scroll actions
  are attributed to their originating windows; same-type split replacement now
  passes experimentally, while retained split return and adaptive hardware remain
  open;
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
  manual errors, logs and mirrored errors, WebView containers, feature flags,
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
- raw intake, reducer output, and product UI give a coherent representation of
  overlapping views inside one application session;
- the iPad probe and backend session both confirm the intended model, followed by
  iPhone Duo validation on iOS 27.1 when that runtime is available.
