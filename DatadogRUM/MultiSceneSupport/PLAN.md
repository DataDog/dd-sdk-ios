# RUM multi-scene implementation and validation plan

Read this document when choosing or executing the next implementation slice,
extending the probes, or checking the release gates. Evidence and current support
levels live in [ASSESSMENT.md](ASSESSMENT.md); chronological run details live in
[EXPERIMENTS.md](EXPERIMENTS.md). Start at the
[canonical overview](../MULTI_SCENE_SUPPORT.md) for the current resume point.

Evidence references use the stable `EXP-*` identifiers from the experiment
ledger; exact run and session identifiers remain in `EXPERIMENTS.md`.

Last updated: 2026-09-12

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
harness. Before running the remaining downstream rows, also add the controls that
do not yet exist: split navigation, restoration, WebView, mirrored
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

## Implementation plan

### 1. Stabilize views, navigation, and actions

- Keep the internal, non-serialized scene identifier and scene-keyed
  `RUMViewsHandler` stacks.
- Maintain one active view branch per scene in `RUMSessionScope`; leave unrelated
  branches untouched during navigation and lifecycle changes.
- Retain the passing UIKit and explicit SwiftUI tap, navigation, modal,
  duplicate-identity, and scene-destruction flows as regression gates. Keep the
  focused disconnect tests, but finish temporary disconnect/reconnect at runtime
  together with UIKit scroll/deceleration, `NavigationSplitView`, restoration,
  and per-scene background/foreground. Action timeout/stop ownership and session
  rollover already have focused and live coverage.
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
  window creation. A candidate fix must produce `ProbeHomeView` and
  `ProbeDetailView` early enough for all six markers per scene, remove the four
  transient fallback views, preserve both active scene branches, and pass three
  clean deterministic runs before expanding the matrix.
- Treat the public lifecycle-hook search as complete unless new Apple API evidence
  appears. LLDB proves navigation titles become observable only after Home work,
  Detail work precedes both hosting-controller and base UIKit appearance callbacks,
  and the apparent iOS 27 reflection replacement reports a registered destination
  while Home is visible. Prepare a bound root/navigation integration proposal for
  API review; do not swizzle SwiftUI internals or ship navigation titles as view
  names.
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
  separate iOS 15/16 integration or infer a scene from global/window ordering.
  Validate the supported behavior on iOS 27/27.1; earlier semantic support is a
  bonus only when it comes from the same uncompromised path.

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
  One separate case remains: a filtered physical interaction supplies synchronous
  scene provenance but emits no action command, so it may not persistently change
  the process representative for later source-less manual APIs.

The current `RUMContextHandoff`, thread-dictionary bridge, synchronous resource
pre-start, captured owner maps, and altered third-party-handler callback path are
provisional. No additional Resource/Trace routing should be layered on them until
the experiment matrix proves which pieces are necessary.

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
Do not spend this project on an iOS 15/16 escape hatch or add either speculatively.
Neither can invent causality when request metadata and application context do not
distinguish a scene.

### 5. Validate, simplify, and regress

- Extend the probe before running cases for which no control currently exists:
  split navigation, restoration, WebView,
  fatal/exported context, and mirrored logger errors.
- Finish only the untested causal-boundary rows: SwiftUI Button -> structured
  `Task`, shared/coalesced work, two-scene reverse completion, and trace-only
  URLSession. Do not repeat structured-task inheritance, source-less schedulers,
  lifecycle fallback, trace teardown, accepted/rejected action, action expiry, or
  operation teardown unless a later change can affect them.
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

- concurrent UIKit, explicit SwiftUI, and automatically tracked native SwiftUI
  windows keep independent, correct view lifetimes;
- stack, modal, split/adaptive, and restored navigation plus tap and scroll actions
  are attributed to their originating windows;
- the trait-backed SwiftUI semantic result survives repeated cold-launch and
  navigation stress; three successful runs are evidence, not a deterministic
  callback-order contract;
- bounded Resource/Trace provenance is validated with actual URLSession timing,
  while unknown-provenance work is explicitly classified and follows the approved
  process-representative fallback;
- RUM Resource and Trace freeze and share one request-start selection whenever a
  trustworthy owner exists, including navigation, rollover, reverse completion,
  and scene closure;
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
