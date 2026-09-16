# Multi-scene rejected approaches

Read the relevant section before designing a new multi-scene implementation or
experiment. These warnings preserve failed, inconclusive, unsafe, or
insufficiently discriminating approaches through `EXP-142` plus active
`EXP-143`/`144` lessons. They are constraints on future work, not a substitute
for the current verdict in
[ASSESSMENT.md](ASSESSMENT.md).

The 107 historical warning blocks below are reproduced from the
[frozen experiment record](Archive/EXPERIMENTS_THROUGH_EXP-142.md) and reorganized
exactly once by subject. Two additional `EXP-142` lessons are included because
they lived in that experiment's detailed record rather than the old warning
section. New `EXP-143`/`144` warnings are appended in their owning subject
sections.

## Thematic index

- [SwiftUI automatic discovery](#swiftui-automatic-discovery)
- [SwiftUI semantic navigation](#swiftui-semantic-navigation)
- [Presentations and manual authority](#presentations-and-manual-authority)
- [UIKit and split navigation](#uikit-and-split-navigation)
- [Actions and causal context](#actions-and-causal-context)
- [Resources and Traces](#resources-and-traces)
- [Operations](#operations)
- [Scene lifecycle and restoration](#scene-lifecycle-and-restoration)
- [Simulator and tooling limitations](#simulator-and-tooling-limitations)
- [Harness mistakes](#harness-mistakes)

## SwiftUI automatic discovery

Late or process-global platform discovery paths that cannot establish semantic destinations.

- Do not let a probe-only hierarchy or measurement reader participate in automatic
  RUM view discovery. Exclude only its exact known type, then retain an adversarial
  check that unrelated customer controllers remain eligible.
- Do not assume `UIView.willMove(toWindow:)` precedes SwiftUI `.onAppear` or the
  synchronous prefix of `.task`. The rebuilt iOS 27 probe proves both can run
  first, and treating every transient detach as a view stop can create duplicate
  sub-millisecond views during navigation.
- Do not retry a child `UIViewControllerRepresentable` as a transparent ordering
  fix. The controller run remained 4-35 ms behind customer lifecycle work, and
  UIKit does not guarantee an ancestor window is available at `viewWillAppear`.
- Do not describe a scene custom trait or `onChange(initial:)` as a transparent
  view-before-callback guarantee. The trait supplies early scene identity and the
  initial callback materially narrows the gap, but two iOS 27 runs still emitted
  the RUM view after customer outer `.onAppear` and immediate `.task`.
- Do not retry moving the unchanged `.trackRUMView` modifier inside or outside
  the screen hierarchy as the early-attribution fix. `EXP-030` and `EXP-031`
  preserve both placements; Detail early work still used Home, and the outer
  placement also left Home early work on `ApplicationLaunch`.
- Do not present `UIHostingSceneDelegate` as transparent automatic navigation
  tracking. `EXP-055` confirms it is an app-owned scene/root lifecycle bridge and
  exposes no destination identity.
- Do not generalize the clean unselected-tab result into a platform guarantee.
  `EXP-036` emitted no false view because that container did not construct the
  offscreen reader. Other aborted, restored, modal, split, or preloaded
  containers still need direct runtime validation.
- Do not retry the `ViewThatFits` rejected-candidate arrangement from `EXP-039`.
  It never constructed the diagnostic `UIViewRepresentable`, so the absence of a
  false RUM view is not evidence about construction without appearance. Use a
  container whose platform child is demonstrably realized or record the case as
  unsupported by available public SwiftUI lifecycle signals.
- Do not count automatic SwiftUI tracking as correct merely because its tap and
  final hosting-controller view use the right scene. Run
  `76f40f1f-554f-4842-86a1-7bf4955b734c` proves the destination is discovered only
  after its lifecycle resources and an extra root view. Preserve both assertions
  in the focused regression.
- Do not retry `UIViewController.viewIsAppearing` as the automatic SwiftUI timing
  fix. The iOS 27-only, multi-scene-only candidate compiled, passed 53 focused
  tests, and still created the final Detail view about 515 ms after `.onAppear`,
  with all lifecycle resources on the source view and the transient root intact.
  It was removed to avoid a new global controller swizzle without semantic value.
- Do not retry a base-`viewWillAppear` hook as the automatic SwiftUI timing fix.
  The scene trait was already correct, but both pre-base run
  `b4bbfa9a-3094-4345-b64e-bb1728bec061` and post-base run
  `20462f01-45d6-4838-9102-151467c4c47f` kept Home work on
  `ApplicationLaunch` and reused the Home exact view ID for all Detail lifecycle
  resources. The hook and tests were removed. Continue from view/name discovery
  or a native SwiftUI integration boundary.
- Do not swizzle the public `UIHostingController.viewWillAppear` override as an
  earlier substitute. LLDB shows both Home and Detail `.onAppear` execute before
  the relevant navigation-host entry. Its correct navigation title therefore
  becomes observable only after the lifecycle work that needs attribution.
- Do not use `navigationItem.title` as the automatic SwiftUI view name. In addition
  to arriving too late, titles can be absent, dynamic, localized, or contain
  customer/user content and are not equivalent to a semantic view identity.
- Do not replace the iOS 27-missing `content.list.item.type` reflection path with
  `elements.body.viewType`. It returns the registered `ProbeDetailView` destination
  type while Home is visible and would create a semantically false destination.
- Do not retry native `WindowGroup` merely to distinguish the Runner lifecycle.
  Runs `native-single-20260912171659` and
  `native-swiftui-20260912171529` already prove the same late discovery in a
  standalone `@main App`, plus B-to-A leakage during `openWindow`. A repeat is
  useful only after changing the discovery or integration boundary.

## SwiftUI semantic navigation

Occurrence identity, path commitment, retained destinations, and transition ordering.

- Do not equate a retained SwiftUI value or `@State` object with one RUM view.
  Returning through navigation must create a new RUM occurrence. `EXP-035`
  validates seven distinct occurrences across three complete push/pop cycles.
- Do not validate a returned navigation occurrence from fresh UUIDs alone. An old
  inactive scope can remain alive for pending Resources and previously matched a
  later start with the same platform lifecycle identity. Keep the `EXP-061`
  pending-Resource regression: Home₁ must remain immutable while Home₂ owns
  new scene work.
- Do not place one semantic tracker as a background sibling, on the whole-stack
  result, or on a stable first child and call it a scene-root solution.
  `EXP-047` through `EXP-049` show that all three remain too late for B's initial
  Home lifecycle; the single whole-stack tracker also replays retained screen
  lifecycle. `EXP-116` is different: its container wrapper owns the root and
  destination builders and injects a separate route-owned boundary at each
  materialized occurrence.
- Do not turn the proven `RUMNavigationStack` prototype into a requirement that
  customers replace native, internal, or third-party navigation. It proves a
  materialization boundary, not ownership of the visual container. Extract the
  occurrence/transition state into a scene-scoped engine and offer an arbitrary-
  view host, optional capability, or explicit source/adapter.
- Do not mirror standard navigation and presentation APIs as `rumSheet`,
  `rumFullScreenCover`, or Datadog-specific destination modifiers. Integration
  cost must scale with containers/routers, not screens or presentations, and
  existing `.sheet`/`.fullScreenCover` code remains valid.
- Do not require retroactive conformance on an imported third-party navigation
  type. It can warn today and conflict with a future library conformance. Prefer
  an explicit reusable adapter or transition source; optional conformance remains
  suitable for customer-owned types.
- Do not claim exact semantics for an opaque container with no accepted-route,
  materialization, transition, router/coordinator, or content-builder signal.
  Keep scene-aware automatic tracking and manual exceptions as the bounded
  fallback rather than inventing navigation state.
- Do not apply `.id` only to the hidden SDK reader to advance a retained route.
  `EXP-093` kept Home's immediate return marker on Detail. The missing input was
  the committed route contraction, not platform-reader identity.
- Do not require a retained route's hidden reader to still be attached when it
  returns. iOS 27 detaches that reader while preserving its SwiftUI state. Keep
  only its last concrete scene, reject `.attached(nil)`, and clear/fence the
  snapshot on scene disconnect as in `EXP-097`/`EXP-098`.
- Do not classify an edge drag as an interactive cancel or finish without a path,
  coordinator, or lifecycle signal. Both bounded `EXP-100` drags were ignored;
  Detail remaining visible alone cannot distinguish cancellation from no gesture.
- Do not serialize a probe path counter as the RUM occurrence identity.
  `EXP-051` showed that retained SwiftUI content can keep the earlier attribute
  value while RUM correctly creates a new UUID. Validate occurrences with view
  start/stop order and distinct UUIDs.
- Do not treat every bound-path write as a committed RUM view. `EXP-052` observed
  two same-turn writes but no materialized destination and correctly retained the
  original Home UUID. Path state is input to semantic tracking, not the event by
  itself.
- Do not equate a same-type destination update with the absence of navigation.
  `EXP-057` visibly committed Detail₂ while RUM retained Detail₁. Name, path,
  attributes, and the outer modifier's freshly generated identity are not safe
  occurrence detectors: ordinary renders can change them, while real occurrences
  can share them.
- Do not prescribe `.id(route)` as the customer fix. `EXP-058` proves that route
  identity is the missing input, but `.id` also resets customer SwiftUI state.
  `EXP-102`/`EXP-103` now prove the same for split selection: a reviewed SDK token
  can rotate only the internal RUM generation while the Detail witness survives.
- Do not classify `delivered=false` from the retained-route source as a failed
  active replacement. Detail₁ → Detail₂ updates one active keyed state and uses
  atomic occurrence replacement; the source is for revealing a previously
  inactive retained route. `EXP-102`/`EXP-103` prove both windows take the former
  path correctly.
- Do not implement token rollover as a normal stop followed by start in
  `RUMViewsHandler`. Removing the top view intentionally restarts the underlying
  stack entry and can synthesize Home between Detail₁ and Detail₂. Replace the
  same-scene stack slot atomically.
- Do not make a missing atomic-replacement source fall back to ordinary add.
  Post-run review of the first `EXP-060` draft found that it could materialize a
  cancelled or stale candidate, stop an unrelated current view, or turn scene
  migration into an implicit add. Missing and cross-scene sources now fail closed;
  a separately proven appearance must use the normal start path.
- Do not treat every unchanged `updateUIView` as a retained-reader remount.
  SwiftUI can update a reader after its semantic view disappeared; only a
  disconnect-rearmed attachment or real appearance may create the next
  occurrence. The first `EXP-064` draft restarted such views.
- Do not consume the retained reader's sole remount signal before an interactive
  transition resolves. Cancellation and a mount/disappear merge must preserve or
  rearm authorization so the next real appearance can create exactly one view.
- Do not attribute cancelled-interactive-navigation view churn to the iOS 27
  early-mount candidate. `EXP-037` reproduced the same false half-second Home and
  Detail restart with the candidate disabled. Fix cancellation as its own
  explicit SwiftUI navigation problem and retain that A/B control.
- Do not wait for SwiftUI's cancellation-reversal callback to discover transition
  state. `EXP-043` found the public UIKit coordinator during speculative Home
  `onAppear`, but it was already gone by Home `onDisappear` and Detail emitted no
  matching callback. Capture `initiallyInteractive` at the first callback and use
  coordinator completion as the commit/cancel boundary; mutable `isInteractive`
  is not the decision signal.
- Do not resolve a recreated destination only through already attached tracked
  readers. Its own reader has no responder ancestry during `makeUIView`; use the
  matching scene hierarchy provisionally, then confirm ownership after attachment.
- Do not group every interactive lifecycle callback in one scene-wide pending
  bucket. Key by coordinator identity and state membership, or a cancelled pop can
  discard an unrelated sheet, tab, or split-subtree occurrence.
- Do not wrap each customer route in a private identity to distinguish repeated values. `EXP-142` showed that this changes the `NavigationStack` element type and breaks ordinary `NavigationLink(value: Route)` / `navigationDestination(for: Route.self)` matching. Preserve the customer's path type and keep occurrence identity inside the materialized RUM boundary.
- Do not model an initially restored `[A, A]` path by constructing two
  simultaneous destination claims in a state-only test. iOS 27 materialized only
  the current top in `EXP-143`; that synthetic construction therefore diagnosed a
  state the platform did not produce. Retain one claim while its position
  survives, and rebase it only when a committed contraction removes its recorded
  position and the same route is the new top.
- Do not remove the never-started reveal fence globally to support a restored
  hidden root. The first `EXP-143` candidate made any registered never-started
  route materializable and failed the full RUM suite. Exempt only a configuration
  explicitly classified as a non-current semantic destination with concrete
  scene proof; ordinary never-started registrations must still fail closed.
- Do not accept a clean restored-path device run as proof that bootstrap
  ownership is race-safe. `EXP-143` fix-c and fix-d both passed 20/20 with correct
  backend ownership, then failed deterministic callback permutations involving
  descriptor lag, replacement readers, disconnect cleanup, and scene movement.
- Do not let a boundary that lent a provisional occurrence fall back to its
  state-local generation fence. Refresh, detach, disappear, and reader-mount
  callbacks for the source-leased donor key must be routed completely by the
  navigation source; otherwise an older callback can expose hidden Root or a
  newer callback can fence the still-visible destination.
- Do not pin a provisional initial occurrence permanently to the first SwiftUI
  reader, and do not require a replacement reader to be virgin. SwiftUI may
  replace and later reuse either reader. A reliable same-scene reader transfers
  the live identity; a scene move or disconnect creates one fresh occurrence.
  Inactive previously used readers are eligible only when their last-started
  generation and local destination or validated donor boundary match.
- Do not use a newer donor boundary as the replacement state's startup
  configuration while its accepted destination descriptor is pending. In the
  rejected fix-d ordering, Root/gen2 prevented the last proven Detail/gen1 from
  restarting. Keep the newer boundary in source metadata and prepare the reader
  with the last proven visible destination.
- Do not stop the live provisional owner before proving that its replacement can
  transfer or restart ownership. The rejected cross-scene fix-d path balanced D1
  and then discovered that the target's same-generation or disconnect fence
  rejected D1, leaving no current semantic view.
- Do not run generic reconciliation before an exact reader-qualified reconnect
  recovery. It can mark appearance without creating an occurrence, consume the
  only remount authorization, and leave later callbacks unable to recover.
- Do not treat the iOS 27 environment scene trait as new ownership proof for a
  dormant semantic boundary. `EXP-143` needs it only as an earlier timing signal
  when a canonicalizing binding reuses a boundary that already has concrete
  reader attachment in that exact scene. Require the exact accepted current
  configuration, reject initial/bootstrap/manual-reveal state, refuse scene
  movement or disconnect recovery, and keep the interactive transition arbiter.
  A broader trait promotion can resurrect stale state or attribute a reused
  boundary to the wrong scene.

## Presentations and manual authority

Target-local authority, nesting, reveal behavior, and automatic coexistence.

- Do not use `TabView` as the sibling-container authority discriminator. Its
  selection/preload behavior cannot prove two simultaneously mounted independent
  navigation branches under the project's one-current-destination model.
- Do not accept a sibling-container run from source layout alone. Require the
  controller-ancestry assertion; missing or collapsed topology is
  `INCONCLUSIVE`.
- Do not implement scene-aware manual views by adding only a scene target to the
  existing direct keyed commands. `EXP-120` proves those commands bypass the
  handler stack and provide no authority over later automatic appearances.
- Do not treat any automatic candidate staged under a targeted manual occurrence
  as a destination worth revealing. `EXP-121` proves that generic hosting
  fallbacks are structural churn. Retain the last semantic destination, reject
  known generic fallbacks during manual authority, and still allow a newly
  trustworthy semantic destination to replace the retained candidate.
- Do not treat exact-scene handler authority alone as presentation deduplication.
  `EXP-123` proves that the automatic presentation hosting controller still needs
  a UI-attached, target-scoped suppression boundary; disabling automatic tracking
  for the entire scene or application is not the required coexistence model.
- Do not use an outgoing RUM view aggregate's final mapper snapshot as the end of
  semantic presentation authority. `EXP-124` proves pending Resources can keep
  that aggregate alive after dismissal while fresh H2 must already own customer
  work. Track router authority and native subtree lifetime as separate intervals.
- Do not end presentation-subtree suppression at the router's semantic stop.
  UIKit can retain the hosting controller through dismissal. Keep the UI-attached
  boundary active until the subtree actually disappears and reject a delayed
  automatic view for that presentation by semantic name (`EXP-125`).
- Do not stop a mounted semantic presentation merely because its binding changes
  directly to another non-`nil` presentation. `EXP-144` baseline exposed Home
  between Sheet and Cover. Retain the last mounted presentation while the new
  value is pending, then atomically replace it only when the accepted replacement
  boundary mounts. If the replacement never mounts, clearing the binding reveals
  from the retained presentation; final container detach must balance it.
- Do not assume SwiftUI calls every outgoing presentation modifier's `onDismiss`
  during direct replacement. The first bidirectional `EXP-144` retry produced the
  correct RUM path but invalidated the harness by beginning one Sheet-subtree
  interval twice. Recorder/suppression diagnostics must tolerate a continuous
  same-style interval and must not let a delayed callback close the currently
  active replacement.
- Do not disable automatic SwiftUI tracking for the entire scene or application
  merely because one semantic/manual boundary is active. `EXP-115` proves the
  viable boundary is an active, attached explicit subtree; unrelated controllers
  must remain eligible, and an inactive or detached reader must not suppress
  automatic discovery.

## UIKit and split navigation

UIKit transition and one-current-destination split-view constraints.

- Do not scope the UIKit split fix only to replacement of a column root.
  `EXP-073` proves that a stable secondary navigation controller produces the
  same false Primary interval on both push and pop. Coalesce the materialized
  outgoing/incoming lifecycle pair within the active column, while starting the
  returned controller as a fresh RUM occurrence.
- Do not accept the initial Primary/sidebar/container views in historical UIKit
  split runs as final product semantics. Those sessions remain valuable evidence
  that the branch removed *restarted* Primary intervals and preserved fresh
  returned destinations, but the approved model forbids structural RUM views
  entirely and the current oracle encodes that negative expectation.
- Do not restore the requirement that a pending UIKit split removal must find a
  tracked controller in another split column. Once structural Primary is
  intentionally absent, S1/S2 navigation has only one tracked column; that guard
  bypasses the coordinator reconciliation needed to distinguish cancel from
  completion.
- Do not count UIKit's second `viewDidAppear` for S2 during a cancelled transition
  as a new RUM occurrence. `EXP-112` proves UIKit may re-deliver appearance while
  RUM correctly retains the same S2 UUID. Use view UUIDs and the coordinator
  result, not callback count alone.
- Do not attach a diagnostic Primary marker after production tracking has
  intentionally suppressed Primary. The marker falls onto the startup fallback
  and creates a false harness attribution failure. Keep Primary lifecycle as a
  probe signal without asking RUM to own Primary work in observable acceptance
  runs.

## Actions and causal context

Trustworthy event provenance, source-less fallback, and delayed action boundaries.

- Do not infer durable asynchronous scene ownership from
  `UITraitCollection.current`. `EXP-135` observes A at SwiftUI callback/task start
  and B after suspension. It is ambient UIKit execution context, not a task-local
  origin token.
- Do not assume a SwiftUI Button closure runs inside the synchronous
  `UIApplication.sendEvent` handoff merely because the tap triggered it.
  `EXP-135` records nil handoff at callback, task start, and task resume. Only a
  task actually created while that dynamic scope is active can inherit it.
- Do not change the strict expected-A `EXP-135` oracle to accept B. B is the
  approved fallback for source-less compatibility, but the scenario deliberately
  records that exact asynchronous origin is unsupported without an explicit
  target or scope. Also use SDK target `SwiftUI_Button`, not the visible button
  title, when counting the automatic tap.
- Do not treat a probe source label on a plain public RUM call as trustworthy SDK
  provenance. `EXP-114` correctly kept such source-less markers on the
  last-interacted representative. Exercise an actual UI-event handoff or an
  explicit target before judging exact scene attribution.
- Do not accept `willDecelerate == true` alone as proof of the late UIKit swipe
  classification path. `EXP-132`'s first completed run omitted the lift-speed
  witness. Require the measured magnitude to meet the SDK's 500 pt/s threshold
  before interpreting an exact `.scroll` at navigation as the ordering result.
- Do not switch from fullscreen B to fullscreen A to prove that an A touch
  overrides representative B. `EXP-089` shows the switch creates a fresh A view
  occurrence and makes it representative before the touch. Keep both scenes
  visibly materialized and interact with A without an intervening appearance.

## Resources and Traces

Asynchronous ownership, indexing, shared requests, and Trace evidence.

- Do not treat a relative-time backend Trace query as absence after the wall clock
  or tool session has advanced. `EXP-133` initially returned zero outside its
  moving window; the exact historical UTC interval found the accepted span and
  its A/B/session predicates.
- Do not treat an exact APM query issued immediately after an accepted upload as
  final absence. In `EXP-134`, RUM events were already searchable while the first
  APM query still returned zero. Retry the same bounded interval through an
  independently indexed attribute such as `@http.url`, then confirm with exact
  count and owner predicates before classifying the run.
- Do not serialize navigation on Resource completion to make a semantic timeline
  look ordered. Resource mapper callbacks describe completed work and may arrive
  after the next view starts; require their exact frozen owner as an eventual fact.
- The shared/coalesced request helper stores one task and does not clear it after
  completion. Relaunch or reset/fix that state before a second shared-request run,
  or it can silently join an already completed task.

## Operations

Application-wide identity, raw-step evidence, and per-step view resolution.

- Do not present local Operation invocation assertions as Operation telemetry.
  Operation-step vitals bypass the public RUM event mappers; require raw and
  reduced backend documents before claiming view attribution or duplicate
  reduction behavior.
- Do not restore permanent start-scene ownership for Operations. It fixed
  same-scene navigation but makes a legitimate A-to-B operation report the wrong
  end view. Retain only a last-proven snapshot and let every trustworthy later
  step replace it.
- Do not use separate simulator-driver processes to race a three-second operation
  against scene closure. Process initialization can reverse the taps. Use AXe's
  ordered `batch` command and fixed toolbar controls; the final teardown run
  proves the intended start-then-close order in console and backend data.
- Do not attribute a missing reduced operation to reducer lag without inspecting
  raw `@type:vital` operation steps. The pre-fix teardown runs had a source-scene
  start and no retained end; the post-fix run has both steps and a reduced event.

## Scene lifecycle and restoration

Scene capability, disconnect/reconnect, restoration, and immutable scope ownership.

- Do not infer support from the integration runner merely having a scene delegate;
  its multiple-scenes flag is false.
- Do not retry the unmodified Example target on iOS 27. It builds but cannot launch
  until its app-delegate-owned window is migrated to the required scene lifecycle.
- Do not use named SDK instances per scene as a shortcut. It would split application
  telemetry and does not solve shared instrumentation or downstream context.
- Do not call an activation request or target `foreground-active` state a focus
  handoff while the peer is still foreground-active. The exact activation row
  requires the peer's latest non-superseded state to become background before it
  judges a fresh occurrence or marker ownership.
- Do not model that peer-state requirement as "the next notification." Either
  valid notification order can occur. Treat the latest exact-scene lifecycle
  value as a latched condition while rejecting any value superseded by a later
  state.
- Do not reuse the initial scene trait as reconnect proof after disconnect. It is
  valid only for the first clean iOS 27 mount. A retained reader must regain an
  attached scene, and an inactive view must still wait for semantic appearance.
- Do not rearm a dormant semantic boundary from a trait or generic update after
  disconnect. Only a reader-qualified concrete attachment proves recovery. A
  queued final detach must retain enough lifetime state to run after the wrapper
  releases, cancel when that state reattaches, and be tested with both reconnect
  orders so stale cleanup cannot remove the fresh owner.
- Do not index a detached observer only by its current scene. Preserve its last
  proven scene for unregister/filter decisions, or a stale A reader can
  participate in B and bypass B's interactive coordinator gate.
- Do not delete all pending state merely because its source scene disconnected.
  A committed migration may already target surviving scene B. Invalidate the A
  occurrence, rebase the B transaction, and let coordinator success or
  cancellation decide whether B materializes.
- Do not trust a changed process environment to replace a restored
  `WindowGroup(for:)` value. The first `EXP-044` launch restored the prior
  `ProbeWindow.runID`, and the rejected first `EXP-138` run proves that even a
  successful uninstall plus absent application container may leave that value in
  the simulator window system. Establish the clean host precondition, normalize
  restored telemetry to the current launch without changing the routed window
  identity, and verify every exact-session view carries the current run ID.
- Do not cite the `EXP-042` force-termination relaunch as concurrent restoration.
  It correctly restored B with the same native scene ID, but iPadOS did not
  reconnect A. A repeat needs a lifecycle/setup that demonstrably restores both
  scene sessions, not another identical terminate-and-launch sequence.
- Do not classify the automatic-run return to SpringBoard after requesting scene-B
  destruction as an SDK crash or proof that scene A was destroyed. The backend
  session reports zero crashes, and this Stage Manager arrangement did not
  automatically foreground the hidden window. Use an explicit restoration or
  activation experiment before drawing a lifecycle conclusion.
- Do not invent a provisional scene ID or rebind an existing RUM view piecemeal.
  Ownership is immutable across the view scope, INV tracker, cache, operations,
  lifecycle maps, and snapshots; ordinary stop/start also allocates a new view ID.

## Simulator and tooling limitations

Environment failures and operating constraints that must not become SDK conclusions.

- Do not retry `make ui-test-podinstall` until the locked bundle has been installed
  with a consistent Ruby toolchain; the failure occurs before pod installation.
- After regenerating Pods with CocoaPods 1.15.2 under Xcode 27, reapply the local
  iOS 15 deployment-target workaround before building the Runner.
- Do not expose or copy values from `Datadog.local.xcconfig` into source, logs, or
  this document.
- Do not classify an expired Xcode/device interaction session as an app or SDK
  crash without a crash report, fatal/assertion output, or crash UI. Preserve it
  as tooling-incomplete and rerun from a clean install, as in `EXP-133`.
- Do not rely on an exact `git add` path list to isolate a checkpoint while the
  local xcconfig is pre-staged. Ordinary `git commit` includes every staged path.
  Use `git commit --only -- <exact paths>` or an isolated index, then verify both
  the commit tree and the xcconfig's original `AM` state.
- Do not claim visual UI state because console logs say a destination materialized.
  The Xcode device-interaction guidance is now available, but the completed
  `EXP-115` session had already expired before its opaque interaction key could be
  handed to the observer. That did not block its auto-driven semantic run or
  read-only OSLog verification. Use a live key plus hierarchy/screenshot or human
  observation for specifically visual claims, and recognized coordinator/path
  evidence for native gesture claims.
- Do not repeat the rapid A/B activation loop on the current iOS 27 simulator.
  `EXP-114` crashed simulator `backboardd` in CoreAnimation/Metal before the
  harness timeout while the probe process stayed alive. Use capable physical
  hardware, and distinguish simulator diagnostics from app/SDK crash reports.
- Do not repeatedly launch `swiftui.coexistence.semantic-a-automatic-b` on the
  current simulator after `EXP-118`. Two clean attempts created the intended B
  automatic hosts, then crashed `backboardd` before the final assertion. Preserve
  the prepared scenario and finish it on physical multi-window hardware.
- Do not repeat `swiftui.coexistence.same-key-manual-two-scenes` on the current
  simulator after `EXP-129`. Its clean run reached distinct A/B native scenes,
  then lost the Xcode/device session amid window-service interruptions before
  manual authority began. The 91/91 hostless contract is useful but cannot
  replace a terminal physical-hardware run and exact backend owners.
- Do not retry `traces.urlsession-shared-request` on the current simulator after
  `EXP-136`. Two explicitly uninstalled runs crashed `backboardd` in the same
  Metal texture-validation path before response release. The second run first
  proved B joined the existing request. Preserve that prefix and run the exact
  132/132 hostless contract on capable physical hardware.
- Do not infer a result after an Xcode device-interaction key expires. The first
  `EXP-126` launch had no captured terminal JSONL or hierarchy; start a newly
  identified, explicitly uninstalled run and classify only that evidence.
- Do not open a short-lived Xcode interaction session before exporting and reading
  its packaged device-interaction skill and preparing the exact measured command.
  A `Session not found` before input is an invalid tooling attempt, not an SDK
  result. The interaction command `help` is unsupported; use the documented
  hierarchy, screenshot, tap, and drag grammar directly.
- Do not use `pgrep` as a process-health discriminator on this simulator image;
  the command is absent. Use a supported process listing or the captured system
  diagnostic before classifying the app as terminated.
- Do not query this probe with `@probe.run_id`; use
  `@context.probe.run_id` or fall back to `service:ios-sdk-multi-scene-probe`
  followed by an exact session-ID query.
- Do not treat `--probe-run-mode clean` as an uninstall or chain acceptance runs
  through Xcode install/run without host teardown. `EXP-117` produced locally
  correct views whose persisted global probe attribute still named the preceding
  run. Explicitly uninstall first, then verify every backend semantic view has
  the requested `@context.probe.run_id`.
- Do not classify the first two-window attempt as an SDK crash: the termination
  reason was a simulator `backboardd` respawn and SpringBoard also restarted.
- Do not keep retrying the same iOS 27 half-and-half window arrangement through
  either Xcode device interaction or Device Hub/CUA. All three attempts caused
  the same system-wide `backboardd` respawn before a full alternating flow.
- After activating the other Device Hub window, refresh the accessibility tree
  before addressing an element by index. A cached B button can still invoke B's
  controller while the screenshot visibly shows A, leaving the representative
  unchanged and invalidating a delayed-provenance experiment.
- Do not treat a successful AXe tap report as simulator interaction while the Mac
  is locked. In run `c28442df-d11a-456b-9ca7-1ffe13bad483`, the accessibility tree
  was readable but the operation controls never invoked and their status remained
  unchanged. Unlock the GUI before resuming the cross-window Operation matrix.

## Harness mistakes

Oracle, recorder, fixture, control, and evidence-design failures.

- Do not consider callback counts, compilation, or crash safety proof of correct
  semantic attribution.
- Do not make an exact `rum-view:<screen>#<occurrence>` driver wait depend only on
  events recorded after the wait step. The mapper may emit the immutable target
  snapshot while the command is being acknowledged. Check already-recorded exact
  evidence first, then subscribe for a later match.
- Do not treat `probe.source_scene` or `probe.screen` as RUM ownership. Those
  fields describe the call site. Only mapper/backend view UUIDs and trusted scene
  association establish where RUM attributed the event.
- Do not treat a mapper callback as persistence or upload proof. It observes an
  event before storage/filtering; retain an exact backend query for support claims.
- Do not fail an unordered completion condition on the first earlier event with
  the same name. Repeated destinations intentionally repeat marker names; keep
  searching for the requested occurrence, then report the earliest ownership
  violation only if no correct event exists.
- Do not require a first RUM view snapshot with `documentVersion == 0`. The live
  structured run first observed Home at version 1, so semantic start is derived
  from the first observed UUID and stop from an active-to-false transition.
- Do not treat the probe scene registry as a shipping SDK fix or serialize its
  future Execution Context seam. It makes exact experiment addressing and joins
  deterministic; production RUM scopes must still preserve their own scene
  ownership, and backend Execution Context serialization is separate work.
- Do not add a second scene-control acknowledgement stream or let `open-window`
  choose an implicit live source. Existing `scene-ready` and disconnected signals
  are the effect acknowledgements; explicit source and target identities keep the
  command itself testable.
- Do not make the scene registry strongly own `UIWindow` merely to stabilize a
  test. The exact-scene test must retain its fixture window just as UIKit retains
  a live application window; weak registry ownership is intentional. Scope any
  `XCTUnwrap` temporary before asserting deallocation because it can extend the
  fixture lifetime under the current compiler/runtime.
- Do not mutate probe SwiftUI state synchronously from `SceneSessionReader`'s
  registration callback. Defer it to the next main-actor turn or SwiftUI reports
  state mutation during a view update.
- Do not add a driver wait for the short Compose occurrence in `EXP-120`. The
  existing direct API can start and stop M1 before the driver observes its next
  condition; the step-bounded authority interval, recorder facts, and semantic
  oracle are the acceptance mechanism.
- Do not report the raw final `EXP-120` H1-stop mismatch as an SDK lifecycle
  failure. The mapper delivered the exact deferred H1 stop after M1's unrelated
  stop. The matcher was fixed to scan onward; the SDK failure is the automatic
  fallback that preempts M1 and owns Compose work.
- Do not use `EXP-053` as SDK replacement evidence. The probe forgot to track its
  new Alternate route in navigation-path mode. Only corrected `EXP-054` exercises
  the intended route-owned boundary.
- The fixed “Other Window” control is predictable only when exactly two sessions
  exist: it selects the first other member of unordered `openSessions`. With more
  windows, verify the recorded target or add explicit target selection first.
- Do not look for restoration, WebView, fatal/exported-context, or mirrored
  `logger.error` controls in the current probe. They do not exist yet; extend the
  harness before scheduling those rows. Stack, SwiftUI split, and UIKit split
  navigation controls do exist and now have signal-driven coverage.
- Do not accept distinct view IDs alone as proof that returned lifecycle work uses the fresh occurrence. The weak `EXP-142` run passed 22/22 only because its marker ran after D3 started; the strengthened reveal-before-callback oracle exposed appearance work still on D2. Preserve weak-oracle runs as non-acceptance evidence.
- Do not append a `waitForSignal` step for a marker that may already have fired
  while an earlier condition was being observed. The first post-fix canonical
  `EXP-143` run reached its correct UI and emitted the delayed marker, then timed
  out because the new wait subscribed afterward. Let the terminal semantic
  completion condition require the action/Resource evidence directly, or wait
  on a discriminator that cannot predate the step cursor.
- `EXP-145` repeats that lesson: attempt A observed `task-delayed` before a later
  duplicate wait and then timed out. Removing only the redundant wait preserves
  the earlier synchronization and the unchanged `EXP-127` control.
- Do not assign one fixed owner to an asynchronous callback that can legitimately
  cross an exact authority stop. `EXP-145` attempt B expected Detail's delayed
  task on manual M1, but it fired after stop and correctly used fresh D1. Use
  explicit under-authority and post-stop markers for acceptance; keep the delayed
  callback diagnostic unless its side of the boundary is itself synchronized.
