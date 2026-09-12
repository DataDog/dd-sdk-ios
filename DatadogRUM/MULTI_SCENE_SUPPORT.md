# RUM multi-scene support assessment

This is the living assessment and experiment log for concurrent `UIWindowScene`
support in Datadog RUM. It is intentionally separate from `RUM_FEATURE.md` until
the behavior is implemented, validated, and ready to become a supported contract.

Last updated: 2026-09-12

## Goal

RUM must correctly represent applications that have two or more independently
navigable windows at the same time. Opening, foregrounding, backgrounding, or
closing one scene must not end or replace the view that remains visible in another
scene. Automatically and manually captured events must be attributed to the scene
that produced them whenever that identity is available.

The primary validation areas are:

1. UIKit and SwiftUI view creation and lifetime.
2. UIKit and SwiftUI navigation, including concurrent navigation stacks.
3. Tap and scroll action attribution.
4. Resource, error, long-task, vital, trace, feature-operation, crash, and
   exported RUM-context attribution; Session Replay crash-free coexistence only.
5. No behavior or performance regression for applications with one scene or no
   scene lifecycle.

The release target for this work is iPhone Duo on iOS 27.1. Correct multi-scene
behavior on earlier systems is welcome when the same implementation provides it
without compromise, but it is not a release requirement. The SDK must continue
to build and behave normally on its iOS 15 deployment target even where semantic
multi-scene support is not claimed.

## Current verdict

**The released baseline is not semantically multi-scene-safe. This branch now has
an experimental core-RUM implementation that fixes the reproduced ownership
failures once a UIKit or explicitly tracked SwiftUI view is established, including
navigation, actions, lifecycle, delayed Resource/Trace completion, and Operations.
Transparent native SwiftUI root and destination creation still fails before those
views exist, so the branch is not ready for a general support claim.** Multiple
real two-window iPad runs and their ingested backend sessions validate the core
model; the remaining matrix and normal-app regressions still gate release. The
pre-trait RUM suite passed 1,018/1,018 after the SwiftUI
attachment and normal-app gating changes. After adding the iOS 17+ trait bridge,
the complete RUM suite passed 1,020/1,020. Logs passed 95/95, Internal 477/477,
Trace 147/147, and WebView 31/31. After the superseding per-step Operations change,
the complete RUM suite passes 1,033/1,033 and the focused manager/session-scope set
passes 98/98.

The iOS 17+ custom-trait experiment now works as an early scene-identity bridge,
but it does not change SwiftUI's outer-to-inner lifecycle modifier ordering. In
two iOS 27 runs, trait-backed tracking made all six Home/Detail lifecycle resources
land on the correct views and `onChange(initial:)` reduced the first-view delay
from about 35 ms to about 3 ms. Customer outer `.onAppear` and the synchronous
prefix of `.task` still ran first. This is a useful attribution improvement, not
a supported view-before-callback guarantee. A stricter follow-up invoked four
synchronous custom RUM actions in those customer callbacks. The view commands
were processed first, all four actions were emitted on the intended new
Home/Detail view, and backend intake agreed. The residual timing gap has therefore
not produced a semantic attribution failure in the tested iOS 27 command/resource
paths.

The probe now has separate manual and automatic SwiftUI tracking modes while it
continues to host SwiftUI inside the integration runner's UIKit `UISceneDelegate`.
Automatic run `76f40f1f-554f-4842-86a1-7bf4955b734c` kept navigation actions and
view activation isolated between scenes A and B, so the branch's scene routing is
effective for hosting-controller discovery. It also reproduced a separate
semantic failure in transparent view creation: Home and Detail `.onAppear` and
immediate `.task` resources completed on the preceding view, after which the
tracker emitted a short-lived `RUMMultiSceneProbeSwiftUIRoot` view and only then
the final navigation-host or destination view. The backend session confirms the
same ordering and attribution. Automatic UIKit-hosted SwiftUI is therefore a
reproduced P0 gap rather than an untested one. Single-window iPadOS 27 run
`5c807364-100d-44b1-8d35-9d5cfd802fc5` independently reproduced the same Home and
Detail sequence in console and backend intake, so it is not specific to the 26.5
runtime used for stable two-window testing.

The native SwiftUI lifecycle is now tested and fails more directly. A standalone
iOS 27 `WindowGroup` probe avoids the Runner's UIKit scene delegate and drives a
bound `NavigationStack` plus `openWindow`. Single-window run
`native-single-20260912171659`, session
`721dcd8f-c88c-44f8-be1b-99d60829da92`, kept Home `.onAppear` and immediate
`.task` on `ApplicationLaunch`; delayed Home work and all three Detail lifecycle
markers used the preceding `NavigationStackHostingController<AnyView>`.
`ProbeHomeView` was never emitted, and `ProbeDetailView` appeared only after all
Detail callbacks. Two-window run `native-swiftui-20260912171529`, session
`ffe3a564-c484-4d2a-b1c7-1e7170d333d0`, then proved the multi-scene consequence:
scene B Home `.onAppear` and immediate `.task` actions and resources were attached
to scene A's final `ProbeDetailView`. Console mapper output and backend aggregates
agree exactly. The branch therefore routes established automatic views by scene,
but transparent native SwiftUI discovery is neither early enough nor semantically
safe while a new window is being created.

An iOS 27-only `UIViewController.viewIsAppearing` experiment was then implemented,
unit-tested, and run against the same probe. It did not move automatic discovery
ahead of SwiftUI lifecycle work: Detail's final automatic view still started about
515 ms after `.onAppear`, all three lifecycle resources stayed on the source view,
and the transient root remained. The extra swizzle and its tests were removed rather
than imposing new controller interception with no semantic gain. Run
`13e39eae-ccc8-47a6-8125-3f52fab589b8`, session
`092c7b63-661e-4f8c-a8ff-b21b92665c96`, preserves the rejected experiment.

A separate base-`UIViewController.viewWillAppear` experiment was also rejected.
LLDB on iPadOS 27 proved that both the outer hosting controller and inner
navigation hosting controller already carry the correct scene trait at the base
interception, even before their own views have a window. Calling the tracker
before the base implementation did not make the initial Home view early enough,
and backend view-ID comparison showed that all three Detail lifecycle resources
still reused the Home navigation-host view rather than a new destination view.
Calling it after the base implementation produced the same semantic result. The
candidate hook and tests were removed. Runs
`b4bbfa9a-3094-4345-b64e-bb1728bec061` and
`20462f01-45d6-4838-9102-151467c4c47f` preserve both orderings.

A follow-up LLDB inspection completed the native Home and Detail timing analysis.
At launch, the generic root `UIHostingController` reached the base
`viewWillAppear` implementation with a nil navigation title and no child
controllers. `ProbeHomeView.onAppear` ran next. Only afterward did
`UIKitNavigationController.viewWillAppear` run, followed by
`NavigationStackHostingController.viewWillAppear` with the correct
`scene-A: Home` title. On navigation, `ProbeDetailView.onAppear` likewise ran
before both `UIHostingController.viewWillAppear` and the base UIKit
implementation. The destination controller and `scene-A: Detail` title already
existed at the callback, but no public controller lifecycle notification had fired
for the SDK to observe. A navigation-title fallback is therefore too late for
Home/Detail lifecycle work even when its eventual value is correct.

The same inspection found iOS 27 private-reflection drift. The existing
`content.list.item.type` path no longer exists. The apparent replacement,
`elements.body.viewType`, exposes the registered destination type and reports
`ProbeDetailView` while Home is still visible. It describes a destination
registration, not the current screen, and must not replace the old path. These
are local runtime/LLDB findings; they do not add a payload or backend result.

The baseline verdict is supported by source inspection and a reproduced iPad
simulator failure: opening scene B emitted a final inactive update for scene A's
still-visible Home view before starting scene B's Home view. In the fixed iPadOS
26.5 probe, opening scene B created a second active RUM view without stopping A;
navigating, presenting, dismissing, scrolling, and closing B affected only B.
UIKit and manually tracked SwiftUI duplicate-name views retained distinct IDs,
and actions plus delayed work stayed on their source windows. Datadog intake
preserved all scene view IDs in one session. The branch keeps one active view
branch per scene and has focused coverage for UIKit and explicit SwiftUI view
lifetimes, duplicate identities, navigation, taps, scrolls, scene lifecycle,
session rollover, and interaction-to-next-view attribution. Mirrored log errors,
WebView native-container correlation, and the representative fatal context have
focused ownership tests.

A teardown-specific experiment found one additional failure after the first core
fix: a scene-owned feature operation emitted its start vital on the correct view,
but closing that scene before the end left no active matching view, so the end
vital was not retained by intake and no reduced operation was created. The manager
now stores the last trustworthy view ID, name, and path proven by any operation
step. Each start, update, retry, success, or failure resolves its call-site view
independently; a trustworthy scene-B step replaces the stored scene-A snapshot.
Only a later source-less or unresolved step falls back to that snapshot, without
resurrecting or updating a stopped `RUMViewScope`. Focused tests cover A-to-B
success and failure, A1-to-A2 navigation, snapshot refresh, teardown fallback,
parallel keys, reverse completion, and process-representative compatibility. Run
`c8d2aa31-127a-4d4c-a910-8e56eea5fb48` remains the backend proof for the closed-
scene fallback; a live A-to-B operation run is still pending.

The Operations review also found that Profiling still correlated operation
messages with the delimiter-concatenated string `name-operationKey`. Distinct
tuples such as (`a-b`, `c`) and (`a`, `b-c`) therefore collided outside the RUM
manager. Commit `ac90b5865` replaces that dictionary key in both continuous and
app-launch profiling with a typed `(name, operationKey)` value, including a
distinct representation for an omitted versus empty key. The complete Profiling
scheme passes 233/233 after this change.

Generic automatic Resource and Trace attribution is **not solved**. An arbitrary
`URLSession` request has no intrinsic `UIWindowScene` identity. The current
`UIApplication.sendEvent` experiment can carry provenance only for synchronous
customer code dispatched by a scene-owned UI event, plus structured child tasks
that actually inherit its `TaskLocal` value. It does not establish ownership for
detached tasks, GCD, timers, repositories, background work, framework-created work,
or other requests that have lost their causal origin. Focused tests and one
button-local resource/span probe show that ownership can be preserved when a
source is known; they do not justify a general automatic-attribution claim.

Important limits remain explicit. Generic source-less manual APIs and feature-
flag messages use the process representative, which normally follows the most
recently tracked interaction. Operation steps first use their last-proven view
snapshot when one exists. Early scene
connection and `viewDidAppear` requests can also reach the previous representative
before the new scene's first RUM view exists; this matches the approved fallback
but is not exact attribution. UI-triggered manual APIs can participate in the
bounded event handoff only when the relevant instrumentation is enabled and the
runtime experiment proves inheritance; callers outside that path remain
inherently ambiguous. Main-run-loop long tasks, hangs, and other process-wide
signals also use one representative rather than being duplicated. Correcting
automatic SwiftUI view discovery, split-view navigation, restoration, profiling
correlation, external-display refresh rate, and iPhone Duo validation remain open.
Session Replay scene-correctness is out of scope; repeated two-window runs uploaded
replay data without an SDK crash, which is the required contract here.

## Resume here

### Checkpoint

The branch is `valpertui/multiple-windows-scenes`. Native SwiftUI probe checkpoint
`e56262485` is committed, and this consolidated assessment is the next isolated
documentation checkpoint. This remains an experimental branch, not a
release-ready support claim.

### Exact next work

1. Prepare the smallest reviewable iOS 27 SwiftUI root/navigation integration
   proposal and validate its semantics against the native `WindowGroup` probe.
   The completed LLDB experiment rules out `navigationItem.title`, the old and
   apparent-new reflection paths, base `viewWillAppear`, and direct
   `UIHostingController.viewWillAppear` as sufficiently early transparent hooks.
   Do not implement a new public API before normal RFC/API review.
2. Complete the Operations public-target API review, including the scene-aware
   manual-key prerequisite. Then run live A-to-B success, A-to-B failure, and
   duplicate-start flows and inspect raw vitals, reduced Operations, and warnings.
3. Prove no normal-app degradation with a live single-scene app, automatic action
   tracking on/off, an ordinary custom URLSession handler, and measured
   `sendEvent` recursion/overhead.
4. Run `NavigationSplitView`, UIKit split/adaptive collapse, UIKit scroll through
   deceleration, per-scene background/foreground, disconnect/reconnect, and
   restoration. Repeat the release matrix on iOS 27.1 and iPhone Duo when that
   destination is available.
5. Close only the missing Resource/Trace causal rows and downstream runtime rows
   listed in the implementation plan. Remove provisional machinery that does not
   change a supported result.

### Proven

Preserve the trait-backed SwiftUI result as a semantic attribution guarantee,
not a callback-order guarantee. Run
`c77883d4-80fe-4730-a3ff-575221a3c262` proved synchronous manual actions and
URLSession resources from outer lifecycle callbacks reach the new view even
though invocation precedes the view payload by 0.3-4 ms. The focused Operations
result is 98/98 across the 26 manager tests and 72 session-scope tests.

### Implemented

- Scene identifiers and routing targets are internal and never serialized.
- Core UIKit and explicit SwiftUI view stacks, session branches, navigation,
  actions, scrolls, INV, lifecycle, session rollover, exact delayed completions,
  WebView containers, feature operations, and representative fatal context accept
  scene-aware routing. Runtime proof varies by surface as recorded below.
- The hidden SwiftUI scene reader and the extra `UIApplication.sendEvent`
  causal handoff are enabled only when the configured application bundle declares
  `UIApplicationSupportsMultipleScenes = true`. Ordinary apps therefore retain
  the original direct SwiftUI modifier and do not activate the extra causal
  handoff. UIKit commands may still carry an internal scene target; live
  single-scene behavior and overhead remain release gates.
- On iOS 17+, a scene-level custom UIKit trait bridges each real scene identifier
  into SwiftUI. An initial trait callback can start tracking before the hidden
  reader attaches and is availability-gated away from the iOS 15/16 build path.
  It does not make an inner tracking modifier run before customer lifecycle
  modifiers applied outside it.
- Runtime SwiftUI evidence covers passing explicit `.trackRUMView` semantics and
  failing `swiftUIViewsPredicate` discovery in both the UIKit-hosted and native
  probes. The rejected `viewIsAppearing` and both base-`viewWillAppear` orderings
  failed to create the intended destination before lifecycle work; Home also
  remains late and transient roots remain. The native `WindowGroup` run additionally proves
  that scene B lifecycle work can inherit scene A's final view before B's first
  hosting-controller view exists.
- Generic source-less work still uses the process representative as compatibility
  behavior. This preserves event volume but is not exact multi-scene attribution.
  Operation steps use their last-proven snapshot before that fallback.
- Feature operations resolve every step independently. Trustworthy call-site
  scene/view context overrides the stored last-proven snapshot, including across
  windows; the snapshot is used only before the process-representative fallback.
  A stopped live view scope is not retained or reactivated. Application-wide
  identity remains the exact `(name, operationKey)` tuple and never includes scene.
- Session Replay is required only to coexist without an SDK crash. Its recording
  semantics remain explicitly out of scope.

### What remains uncertain

- The exact reviewed integration that can publish native SwiftUI root and
  navigation identity before customer lifecycle work. Public Apple lifecycle
  hooks inspected so far are too late; unsupported reflection and private SwiftUI
  swizzling are rejected.
- Whether a physical interaction rejected by the action predicate should still
  persistently advance the representative used by later source-less APIs.
- Whether split-view panes are one semantic RUM view per scene or multiple
  simultaneously active views.
- How product UI and analytics should present overlapping views from one session.
- The final Swift/Objective-C Operation target API names and whether scene-aware
  manual keyed-view start/stop ships in the same API review.
- The unrun navigation, lifecycle, downstream-signal, normal-app, iOS 27.1, and
  iPhone Duo release rows listed in the plan and completion gates.

All rejected experiments and their rationale live in the authoritative
`Attempts not to repeat` section below.

### Blockers and workspace safety

There is no active commit-signing blocker: after two earlier communication
failures, signed commit `e56262485` succeeded. Never use an unsigned fallback if
the signer fails again. Public SwiftUI and Operation API work remains blocked on
normal RFC/API review. The iOS 27 integration-runner half-and-half arrangement
also caused repeated simulator-wide `backboardd` respawns, although the standalone
native `WindowGroup` probe can open two windows on iOS 27.

Do not stage or commit
`Datadog/Datadog.xcodeproj/project.pbxproj` or
`xcconfigs/Datadog.local.xcconfig`; they predate this work, and the latter contains
local credentials. The integration-test project change is part of the probe.

Checkpoint validation on 2026-09-12:

- `DatadogRUM`: 1,033/1,033 passed after the per-step Operations attribution and
  fallback-precedence change, with zero failures, skips, expected failures, or
  tests not run.
- Operations-focused tests: 98/98 passed, comprising 26/26
  `RUMFeatureOperationManagerTests` and 72/72 `RUMSessionScopeTests`.
- `DatadogInternal`: 477/477 tests passed.
- `DatadogLogs`: 95/95 tests passed.
- `DatadogTrace`: 147/147 tests passed.
- `DatadogWebViewTracking`: 31/31 tests passed.
- `DatadogProfiling`: 233/233 tests passed after replacing concatenated Operation
  correlation keys with exact typed identities.
- `RUM MultiScene Probe`: the current tree rebuilt successfully through Xcode 27
  in 2.799 seconds with zero errors after adding fixed cross-window Operation
  controls and the manual/automatic SwiftUI mode switch.
- `Datadog-Package`: generic iOS Swift Package build passed through Xcode 27.
- Repository lint passes with zero violations across 713 source and 699 test
  files; `git diff --check` is clean after the current Operations edits.

## Checkpoint commit structure

The branch history and current checkpoint are intentionally split by rollback
boundary, in this order:

| Order | Commit subject | Boundary |
| --- | --- | --- |
| 1 | `Route RUM state through concurrent scenes` | Core scene/view/action/lifecycle/session/cache/operation model, plus the private execution-local handoff and focused tests |
| 2 | `Preserve scene ownership for RUM resources` | Network interception and URLSession RUM resource start/completion ownership |
| 3 | `Preserve scene ownership for logs and mirrored errors` | Log correlation and delayed log-to-RUM error routing |
| 4 | `Preserve scene ownership for trace correlation` | Manual spans, URLSession spans, propagation correlation, and completion ownership |
| 5 | `Preserve native scene ownership for WebView RUM` | Native container snapshots forwarded with WebView events |
| 6 | `Add a multi-scene RUM integration probe` | Runner scenario, multi-window scene delegate support, scheme, and project wiring |
| 7 | `Document the multi-scene support checkpoint` | This assessment, experiment ledger, rejected paths, plan review, questions, and resume instructions |
| 8 | `Bridge native scene identity into SwiftUI` | iOS 17+ custom trait publication, SwiftUI environment bridge, normal-app gating, and focused tests |
| 9 | `Preserve feature operations after scene teardown` | Last-proven source-view snapshot, teardown/navigation/legacy tests, and no live-view resurrection |
| 10 | `Add fixed multi-scene probe controls` | Fixed UIKit/SwiftUI activation and close controls used by delayed-work and teardown experiments |
| 11 | `Update the multi-scene runtime assessment` | Consolidated run/session evidence, operation failure and fix, current gaps, validation, and resume plan |
| 12 | `Add automatic SwiftUI multi-scene probe mode` | Manual/automatic probe selection and conditional explicit SwiftUI view tracking used by the transparent-tracking experiments |
| 13 | `Support cross-window RUM operation attribution` | Per-step trustworthy-view resolution, exact scene-independent identity, duplicate-start semantics, focused regressions, and A/B runtime controls |
| 14 | `Preserve exact RUM operation identity in profiling` | Exact `(name, operationKey)` correlation in continuous and app-launch Profiling, including delimiter and omitted-key collision coverage |
| 15 | `Automate SwiftUI navigation probe and document findings` | Deterministic automatic navigation, rejected early UIKit lifecycle hooks, exact-ID backend evidence, and resume guidance |
| 16 | `Add native SwiftUI multi-scene probe` | Standalone iOS 27 `WindowGroup` harness plus single-window and two-window backend baselines |

Rows 1-16 are committed. Row 16 is commit `e56262485`.

Because `xcconfigs/Datadog.local.xcconfig` already has a user-owned staged entry,
each checkpoint commit must use an exact path list. Do not use a broad `git commit`
or alter that file's staged/working-tree state.

## Consolidated experiment ledger

The chronological notes below retain full IDs and observations. This table is the
authoritative index of runs that currently support decisions:

| Probe run | RUM session | Runtime | What it established |
| --- | --- | --- | --- |
| `a9fab1c4-5cb6-4468-9d1a-dc0936116c46` | `18e48c14-7073-4353-9b85-0121b93c74e0`, `5fc61f1f-9253-4c12-9917-d1568e4ca9d5`, and `86a1a492-24db-485c-80dc-1a4a21dab1e7` | iPadOS 27 | Single-window harness, payload markers, and backend queries work. Three second-window attempts ended in simulator-wide `backboardd` respawns; the second captured baseline scene B replacing still-visible A first. |
| `574be7dd-4482-48e5-b4cc-eaaa332179bd` | `59a3329e-1a21-486c-9ee5-190d111bfbf3` | iPadOS 26.5 | First fixed two-window proof: A and B views coexist; B navigation does not stop A; delayed resource/span/operation retain the intended B lifecycle. |
| `4d7dc23b-721d-4038-8c89-3b29a1c373c9` | `0caa932a-7c4c-4c9d-9fb5-4acb691118f9` | iPadOS 26.5 | Manual B action emits once instead of fanning into A; mixed UIKit/SwiftUI navigation remains scene-isolated. |
| `6a0b61d0-85a8-4915-b02e-63ab53fa13db` | `2b282934-aae9-4495-b7fc-797736f58735` | iPadOS 26.5 | Concurrent UIKit and SwiftUI views coexist; Session Replay uploads are accepted with no SDK crash. |
| `e7bf0f3e-2e46-4487-af4f-072cd7ba8ab8` | `feb94679-4b2e-4821-8146-a531e8608672` | iPadOS 27 | Physical SwiftUI navigation action and destination are correct in one scene; opening B reproduces the simulator compositor crash, not an SDK crash. |
| `da902d8a-f16e-4fa9-b82c-8dcdbaa6dc5f` | `5e65abff-6999-45b2-b8ca-cf199b1b13e4` | iPadOS 26.5 | Actual URLSession boundary: synchronous UIKit work and task resume can retain B; scene connection and `viewDidAppear` loading can fall to representative A. |
| `8a71b04b-ee69-4670-bdb1-28a6a3625662` | `462f633d-b3fb-4fd5-83e6-bd83123187ee`, then `2df86288-72c8-43dc-ab53-7d13d70c6367` | iPadOS 26.5 | Structured requests retained B and correctly kept/dropped their action at 20/200 ms. The same run exposed the pre-fix explicit-session-stop loss of still-visible scene A. |
| `e03e31d3-eb19-4955-9782-1b583f37b28f` | `29784a34-5196-4ed1-8c56-8e3337f31205` | iPadOS 26.5 | Explicit session stop restores both active scene branches; delayed B work remains on B after navigation. |
| `70ccd6cf-1514-4387-86ef-25cc255744c4` | `8ea9108c-3fb3-4cdf-ae76-c429348b16b0` | iPadOS 26.5 | Three-minute causality proof: structured `Task` retains B; detached task, GCD, and timer use representative A. RUM and APM agree. |
| `5ebc59df-6fc1-4620-bcb2-1177d9ab3409` | `d49d1cdf-5a6d-4787-af1e-1422ec841ea4` | iPadOS 27 | SwiftUI `.onAppear` requests precede the tracked view and land on the preceding view; delayed task work is correct. |
| `fd44bcd2-cde3-4488-a9f4-7756683d85f4` | `dab21bf2-8fee-406a-bd84-81b7211e934e` | iPadOS 27 | `UIView.willMove(toWindow:)` remains too late for `.onAppear` and immediate `.task`; pre-correction navigation emitted a 0.79 ms duplicate Home. |
| `16e48aa6-6826-49ea-b764-6c0af6f16c0b` | `c8c5b90c-ef71-4bbe-842a-fa22ed5587fd` | iPadOS 27 | Child-controller bridge also remains too late. It avoided synthetic/duplicate views in this run and stayed crash-free, but offered no ordering benefit and was removed. |
| `68786559-42b4-4087-8e34-997e77d081c5` | `799d975d-9597-4b2e-9c4e-833835aed5de` | iPadOS 27 | Scene custom trait reached SwiftUI before the hidden reader and all six Home/Detail lifecycle resources resolved to the correct view, but outer callbacks still preceded the RUM view by 35/34 ms on Home and 2/1 ms on Detail. |
| `92326a81-441e-48b9-97b3-3db2b00bc3ab` | `4bd7fa85-dda2-4712-9cce-33cb23f73a3c` | iPadOS 27 | Adding `onChange(initial:)` reduced the callback-to-view gap to 2-3 ms for both Home and Detail. It still did not invert lifecycle ordering; backend intake nevertheless preserved all six resources, the source Home navigation action, four expected views, and zero errors/crashes. |
| `c77883d4-80fe-4730-a3ff-575221a3c262` | `67fdbd11-1d6a-440d-afd0-db11ff6bc6c4` | iPadOS 27 | Four synchronous custom RUM actions invoked in customer outer `.onAppear`/immediate `.task` before the view payload were all processed on the intended new Home/Detail view. Six lifecycle resources were also correct; five total actions, zero drops, zero errors/crashes. |
| `91864fb5-cace-4f29-a348-5769bf2ffa65` | `02b150f8-3b2f-43fd-b032-8cac2ef91cd9` | iPadOS 26.5 | SwiftUI scene B navigation and delayed operation/resource work remained on B while scene C opened. Scene C's connection and initial lifecycle resources used the previous representative B view, confirming the source-less early-scene boundary. |
| `31d0a951-095a-4a71-8c48-b6e4fb4d0af2` | `3160c14e-95d7-4a0e-a40b-204060cfae45` | iPadOS 26.5 | UIKit modal presentation/dismissal and duplicate-name A/B views remained independent. The first delayed-work switch attempt was invalidated by a stale scrolled control, which led to fixed toolbar controls in both probe UIs. |
| `76599137-09c8-4fb1-b54a-92b3c9ff04d1` | `725418d9-aae5-4570-8bd0-1bad452bbb8c` | iPadOS 26.5 | Using the fixed toolbar switch, a UIKit B trace and operation kept B Home ownership while A became active. APM trace `6aa50e250000000095c6c6caacd03265` retained resource `probe-span-scene-B`. |
| `972c83f7-9c13-4ea3-b5b6-d43857bb7815` | `3a8b0c3b-53e4-4426-b4b1-12e92ec715d5` | iPadOS 26.5 | Broad UIKit/SwiftUI teardown matrix: 18 views, 17 actions, 33 resources, 4 long tasks, zero errors/crashes, and replay available. Duplicate views, modals, SwiftUI scroll, delayed resources, and both UIKit/SwiftUI traces stayed scene-correct. Raw operation starts survived, but operation ends after scene closure did not, exposing the teardown gap. |
| `c8d2aa31-127a-4d4c-a910-8e56eea5fb48` | `6c05508c-18fc-41df-85e8-32c573fbf37e` | iPadOS 26.5 | Post-fix teardown proof. Operation key `206E691E-33AC-4BF1-8D26-E48D81315D9A` started in scene D, D closed one second later, and intake retained both raw steps on D Home view `547eb0b9-5743-47f7-ab07-c309e5b5bb29`. The reducer produced one successful 3.15-second operation with the same start/end view. Session counts: 8 resources, 8 views, 7 actions, 3 vitals, 1 long task, 1 operation, 1 session; replay available. |
| `76f40f1f-554f-4842-86a1-7bf4955b734c` | `ae9530b4-4117-4895-a1fe-7442a160e76f` | iPadOS 26.5 | First concurrent automatic-SwiftUI run using `DefaultSwiftUIRUMViewsPredicate`. Scene-A and scene-B taps and reactivation stayed isolated, but Home and Detail lifecycle resources landed on the preceding view. Each initial transition emitted a transient `RUMMultiSceneProbeSwiftUIRoot` before the final navigation-host or destination view. Closing B sent its late detached callbacks to `Background`, not scene A. Backend intake matches the console sequence; Session Replay remained available and no SDK crash was recorded. |
| `5c807364-100d-44b1-8d35-9d5cfd802fc5` | `2133b271-2079-4d9c-b570-fcea81e1f062` | iPadOS 27 | Target-runtime automatic Home -> Detail reproduction without opening a second window. Home `.onAppear` and immediate `.task` remained on UIKit Home; Detail's three lifecycle resources and tap remained on its source navigation host. Both transitions then emitted transient root and final destination views. Backend: 21 events, 6 views, 8 resources, 1 action, zero errors/crashes, replay available. |
| `13e39eae-ccc8-47a6-8125-3f52fab589b8` | `092c7b63-661e-4f8c-a8ff-b21b92665c96` | iPadOS 27 | Rejected `viewIsAppearing` experiment. Home `.onAppear` and immediate `.task` remained on UIKit Home; all three Detail lifecycle resources remained on the source navigation host; transient roots remained. The final Detail view started about 515 ms after `.onAppear`. Steady-state manual action/resource attribution remained correct, uploads returned 202, replay was available, and no crash occurred. The extra swizzle was removed. |
| `b4bbfa9a-3094-4345-b64e-bb1728bec061` | `ae51b4e7-c88b-4413-98bb-455f93c38dd6` | iPadOS 27 | Rejected pre-base-`viewWillAppear` candidate. Home `.onAppear` and immediate `.task` used `ApplicationLaunch`; its delayed task and all three Detail lifecycle resources reused Home navigation-host view `7f2ca0fc-31fe-4902-bafb-7a7029b2758c`. Intake contains 17 events, 5 views, 7 resources, zero errors/crashes, and replay. Exact IDs disprove a destination-view fix despite the repeated host name. |
| `20462f01-45d6-4838-9102-151467c4c47f` | `da12ef5f-539e-4821-afa9-c2814e63be91` | iPadOS 27 | Rejected post-base-`viewWillAppear` ordering. Home lifecycle work remained on `ApplicationLaunch`; its delayed task and all three Detail resources reused Home host `445ec932-6eb3-49bf-a25b-aff6bacbc29a`. Backend contains 16 events, 5 views, 7 resources, zero errors/crashes, and replay. The hook was removed. |
| `0b5749cf-e4fd-4bd5-a3e8-4789d3ee6d97` | `cc9e9e0c-1f85-401b-9f33-ba66843b9e50` | iPadOS 26.5 | Same-binary manual-mode control after adding the switch. Explicit tracking emitted `SwiftUI scene-A Home` before completion of its three lifecycle requests; all three backend resources use that view. Twelve ingested events, zero errors/crashes, and replay available confirm the default path remains unchanged. |
| `native-single-20260912171659` | `721dcd8f-c88c-44f8-be1b-99d60829da92` | iPadOS 27 | First standalone native SwiftUI single-window control. Home `.onAppear` and immediate `.task` actions/resources used `ApplicationLaunch` `9514e96c-4cf8-4efb-a55e-35c58ba4b61e`; delayed Home plus all three Detail phases used navigation host `2810e9e8-9676-4b6b-8838-c8efb78b00ad`. `ProbeHomeView` never appeared; final `ProbeDetailView` `9387c0d9-f0f2-4010-afb0-8f84e17e4275` started after the callbacks. Backend preserved all 6 actions and 6 resources across exactly those mappings, 5 views total, and zero view crashes/errors. |
| `native-swiftui-20260912171529` | `ffe3a564-c484-4d2a-b1c7-1e7170d333d0` | iPadOS 27 | First native `WindowGroup` plus `openWindow` proof. Scene A and B received distinct native sessions, but B Home `.onAppear` and immediate `.task` actions/resources used scene A Detail view `b33cbe9a-4613-4327-9e2f-a6ceadba5896`. B's own navigation host `5ed90c94-ebd0-491b-bb81-24d4b846468a` appeared afterward and received delayed Home plus all Detail lifecycle work; final B Detail `c7a46015-aa45-4d4e-a280-7b6e989f469a` started later. Backend preserved the exact 12-action/12-resource mapping, 9 noisy views, and zero view crashes/errors. |
| `lldb-native-lifecycle-20260912` | Not applicable | iPadOS 27 | Local LLDB timing/reflection inspection. Root base `viewWillAppear` had no title or children, then Home `.onAppear` ran before the navigation-controller/host callbacks. Detail `.onAppear` ran before both hosting-controller and base UIKit callbacks. Titles were correct only at the later host boundary. `content.list.item.type` is gone, while `elements.body.viewType` falsely exposes registered `ProbeDetailView` while Home is visible. No backend claim is attached to this experiment. |

## Objective progress review

This review measures the branch against the initial support objective rather than
against the amount of implementation completed:

| Objective | Current evidence | Remaining release work |
| --- | --- | --- |
| Concurrent view creation and lifetime | UIKit and explicit SwiftUI `.trackRUMView` windows coexist in one RUM session; established automatic hosting-controller stacks retain scene isolation | Native `WindowGroup` proves B startup work can inherit A's view before B discovery. LLDB rules out title, current reflection paths, and controller appearance callbacks as early transparent sources. Review an explicit iOS 27 integration before restoration and iPhone Duo validation |
| UIKit and SwiftUI navigation | UIKit push/pop/modal and manually tracked SwiftUI `NavigationStack`/modal flows have independent backend view chains, including duplicate names; automatic navigation remains scene-local once its host exists | Correct native automatic root/destination creation and attribution through a reviewed integration, plus `NavigationSplitView`, UIKit split/adaptive collapse, and restoration |
| Action attribution | UIKit/SwiftUI taps emit once on the source view; SwiftUI scroll, action rejection, action expiry, and overlapping-action fixes have backend or focused-test proof | UIKit scroll through deceleration and the filtered-physical-interaction representative edge |
| Scene lifecycle and sessions | Requested scene destruction/close affects only its scene; focused tests cover disconnect; explicit stop and expiry restore concurrent branches; overlapping views reached raw intake and the reducer | Temporary disconnect/reconnect, per-scene background/foreground, restoration, and product UI presentation of overlapping views |
| Resources, traces, and operations | Known Resource/Trace provenance is frozen through completion. Operations use application-wide typed identities and independently resolve each step; focused A-to-B, parallel-key, reverse-completion, navigation, teardown, and compatibility tests pass | Four unrun Resource/Trace causal rows, live A-to-B/duplicate-start Operation proof, public Operation target API review, and generic source-less representative fallback |
| Errors, logs, WebView, vitals, fatal/exported context, and profiling | Scene-aware source or focused tests exist for each except profiling, whose process-level limitation is known | Targeted two-window runtime/backend evidence; profiling needs an explicit support statement, not guessed per-scene ownership |
| Normal-app compatibility | Full RUM/Internal/Logs/Trace/WebView suites, gating regressions, probe build, lint, and generic iOS package build pass | Live single-scene behavior, custom-handler integration, and `sendEvent` overhead/recursion measurement |
| Session Replay | Multiple UIKit/SwiftUI two-window and teardown runs uploaded replay data without an SDK crash | No scene-correctness work required for this objective |

The core model is no longer the largest unknown. The release-critical work now
starts with the reproduced automatic SwiftUI view-creation/navigation failure,
then the remaining navigation/lifecycle/action rows and proof that ordinary apps
do not pay a behavioral or performance cost. No additional distributed-tracing
or header-repair work is justified unless one of the pending causal experiments
reproduces a RUM/APM ownership disagreement.

### Required causal-boundary experiment status

This table records every case requested by the product clarification. “Classified”
means the observed representative fallback is the intended compatibility result,
not exact source attribution.

| Required case | Evidence | Status / next action |
| --- | --- | --- |
| Synchronous URLSession request in a UIKit tap | Run `da902d8a-f16e-4fa9-b82c-8dcdbaa6dc5f` kept RUM Resource, APM span, source view, and accepted action together | Backend-pass |
| Structured `Task` created in a tap, including suspension | Run `8a71b04b-ee69-4670-bdb1-28a6a3625662` proved 20/200 ms action validity; run `70ccd6cf-1514-4387-86ef-25cc255744c4` retained scene B across three minutes and a representative switch | Backend-pass |
| `Task.detached`, GCD, and timer | Run `70ccd6cf-1514-4387-86ef-25cc255744c4` put all three on representative A rather than source B | Backend-classified as source-less |
| SwiftUI Button followed by structured `Task` | The control exists, but no isolated two-window backend result distinguishes it from the broader SwiftUI delayed-work runs | Pending |
| SwiftUI `.task` and `onAppear` loading | Pre-trait explicit runs `5ebc59df-6fc1-4620-bcb2-1177d9ab3409`, `fd44bcd2-cde3-4488-a9f4-7756683d85f4`, and `16e48aa6-6826-49ea-b764-6c0af6f16c0b` failed; trait runs `68786559-42b4-4087-8e34-997e77d081c5`, `92326a81-441e-48b9-97b3-3db2b00bc3ab`, and `c77883d4-80fe-4730-a3ff-575221a3c262` achieved correct explicit attribution. Automatic UIKit-hosted and native runs put lifecycle work on preceding views. LLDB then proved Home/Detail `.onAppear` precede the usable navigation-host appearance boundary | Backend-pass for explicit tracking on iOS 27; automatic initial-root and destination attribution fail; explicit integration review next |
| Scene connection and UIKit `viewDidAppear` loading | Runs `da902d8a-f16e-4fa9-b82c-8dcdbaa6dc5f` and `91864fb5-cace-4f29-a348-5769bf2ffa65` used the prior representative before the new view existed | Backend-classified as source-less |
| Pre-created URLSession task resumed from a UI action | Run `da902d8a-f16e-4fa9-b82c-8dcdbaa6dc5f` selected B Detail and the resume action at interception rather than object creation | Backend-pass |
| One shared/coalesced request used by both scenes | Probe control exists; no conclusive two-window run | Pending; expected to remain ambiguous |
| Navigation and session rollover before actual request start | Navigation-at-resume passed in `da902d8a-f16e-4fa9-b82c-8dcdbaa6dc5f`; `8a71b04b-ee69-4670-bdb1-28a6a3625662` exposed rollover loss and `e03e31d3-eb19-4955-9782-1b583f37b28f` verified the fix | Backend-pass |
| Reverse-order completion from two scenes | RUM and Trace focused tests pass with frozen A/B owners | Runtime/backend pending |
| Source scene closes before completion | Run `972c83f7-9c13-4ea3-b5b6-d43857bb7815` preserved delayed resources and traces; run `c8d2aa31-127a-4d4c-a910-8e56eea5fb48` preserved the fixed operation | Backend-pass |
| Concurrent operations with identical `(name, key)` | Contract decided and focused test passes: the second start emits normally and replaces only local tracking; one later end closes the latest start, with no synthetic client-side end | Live warning/raw-vital proof pending; the earlier backend operation is expected to remain open until its four-hour timeout |
| Trace-only URLSession span | Probe control and four Trace ownership regressions exist | Runtime/backend pending |
| Action accepted, rejected, already active, and expired | Runs `da902d8a-f16e-4fa9-b82c-8dcdbaa6dc5f`, `574be7dd-4482-48e5-b4cc-eaaa332179bd`, `4d7dc23b-721d-4038-8c89-3b29a1c373c9`, and `8a71b04b-ee69-4670-bdb1-28a6a3625662` cover accepted/filtered, fan-out failure/fix, and expiry | Backend-pass; filtered-tap representative persistence remains separate |
| Single-scene and custom URLSession-handler compatibility | Complete module suites and 43 resource-handler tests pass; the rejected request-rewrite experiment was removed | Live single-scene, custom-handler integration, and performance pending |

## Baseline environment

| Item | Baseline |
| --- | --- |
| Branch | `valpertui/multiple-windows-scenes` |
| Baseline commit | `92f021ba7e4a866f84a52da93ed8b63f3dc75882` |
| SDK deployment target | iOS 15.0 |
| Xcode | 27.0 (27A266a) |
| Simulator | iPad Pro 13-inch (M5), iOS 27.0 |
| Backend access | Datadog RUM search and aggregation tools available |
| Local credentials | Read from `xcconfigs/Datadog.local.xcconfig`; values must never be copied here |

Pre-existing working-tree changes at the start of this assessment:

- `Datadog/Datadog.xcodeproj/project.pbxproj` was modified.
- `xcconfigs/Datadog.local.xcconfig` was staged as a new file and also modified.

Both are treated as user-owned and must not be reverted or exposed. Any project
file edits made by this work must be distinguished from that baseline.

## Existing support assessment

### View instrumentation and navigation

`RUMViewsHandler` owns one process-wide `stack`. When a view appears, it stops the
last view in that stack before starting the new one. When a view disappears, it can
restart only the previous item in that same stack. There is no scene identity in
the stored view or in `RUMStartViewCommand` / `RUMStopViewCommand`.

Consequences for two visible windows A and B:

1. A starts view A1.
2. B starts view B1 and the SDK stops A1 even though A1 remains visible.
3. Navigation in A starts A2 and stops B1 even though B1 remains visible.
4. A disappearance can reveal or restart a view from B because the histories are
   interleaved in one stack.

UIKit callbacks retain a `UIViewController`, from which a `UIWindowScene` can
usually be determined. Automatic actions receive a `UIEvent` and touch view, which
also normally retain window/scene identity. Today that information is discarded.

SwiftUI modifier callbacks carry only a string view identity or action name. The
same modifier identity used in separate windows can therefore collide, and there
is no scene identity at the command boundary. Automatic SwiftUI navigation is
ultimately observed through hosting view controllers and has the same global-stack
problem. `NavigationSplitView` coverage must be validated separately.

### Session model and downstream attribution

`RUMSessionScope` can keep several view scopes, but exposes one `activeView` chosen
from the most recently active scope. Starting a new view deactivates the previously
active view. Commands without their own view identity are processed against that
single active view.

This affects at least automatic actions, manual actions, scrolls, resources,
errors, long tasks, vitals, feature operations, interaction-to-next-view metrics,
Session Replay context, tracing correlation, crash/fatal context, and the public or
internal RUM context exported to other SDK features. Some event types have their
own asynchronous context capture and may behave better than this baseline implies;
each must be tested rather than assumed.

### Lifecycle

View instrumentation currently observes process-level application background and
foreground notifications. A scene becoming inactive, entering the background, or
disconnecting is not equivalent to the whole application doing so. Conversely,
closing one scene must not stop unrelated scenes or end the process session.

The integration runner has a `UISceneDelegate`, but its Info.plist explicitly sets
`UIApplicationSupportsMultipleScenes` to `false`. It can exercise scene lifecycle
plumbing but cannot validate two concurrent windows. The Example target has no
scene manifest and creates one app-delegate-owned window.

### Downstream correlation surfaces

The global active-view assumption is reused well beyond view instrumentation:

- **Resources and network tracing:** `URLSessionRUMResourcesHandler` and
  `URLSessionTaskInterception` preserve request and trace state but no originating
  RUM view or scene. An automatic or manual resource start therefore resolves
  against the process-wide active view. Simply allowing several scopes to remain
  active would duplicate one resource into every active view unless routing is
  made explicit.
- **Logs and mirrored RUM errors:** `RemoteLogger` snapshots one exported RUM
  view/action context. When an error log is mirrored into RUM, the message does
  not carry that captured view, so `ErrorMessageReceiver` resolves the view again
  later. The log and corresponding RUM error can disagree after a scene switch.
- **Traces:** spans snapshot the singular exported RUM context. Trace-only
  URLSession spans are constructed at completion with a historical start time,
  which means their RUM view can come from the scene active at completion rather
  than the one that initiated the request. Trace parentage is more robust because
  active spans are execution-scoped, but the RUM correlation remains global.
- **Feature operations and feature flags:** commands and message-bus payloads do
  not carry a scene or view target. Feature-operation lifecycle keys are also
  process-global, so equal operation keys used concurrently by two scenes can
  collide.
- **Session Replay:** `KeyWindowObserver` flattens all connected scenes and picks
  the first key window. Multiple scenes can each have a key window and set order
  is not stable. A single recording coordinator then combines that arbitrary
  window with one global RUM context, while the recorder can drop overlapping
  requests. Captures, touches, and RUM view IDs can therefore refer to different
  windows.
- **Web views:** the bridge receives the exact `WKWebView` but retains only its
  hash. Native-container selection later uses a global timestamp-only
  `ViewCache`, so browser events from one scene can be stitched to another
  scene's native view.
- **Vitals and interaction-to-next-view:** each concurrent view would sample the
  same process readers; refresh-rate collection uses `UIScreen.main`, which is
  additionally wrong for external displays. `INVMetric` keeps one current view,
  making a navigation in scene B the successor of an interaction in scene A.
- **Crashes, fatal hangs, watchdog termination, nonfatal hangs, long tasks, and
  memory warnings:** these signals are process-wide and often have no unique
  scene. Current persistence and fatal context retain only one view. They need a
  deliberate representative or de-duplicated multi-view policy; broadcasting
  would inflate event counts.
- **Profiling:** one profiler per process remains appropriate, but its mutable
  RUM attributes are last-writer-wins while event identifiers can span several
  views. Correlation should aggregate active view IDs or retain ownership per
  event rather than multiply profilers.

Application sessions, sampling decisions, timeseries collection, upload, and the
aggregate application lifecycle should remain process-wide. Scene support must
not multiply these facilities.

### Compatibility constraints

- Keep one application-level RUM session unless experiments reveal an unavoidable
  backend contract problem. Concurrent windows should normally be concurrent view
  branches inside that session, not separate SDK instances.
- Scene identity should remain internal metadata unless a separate public/backend
  contract is approved.
- Commands that have no scene identity must retain today's behavior until a safe
  attribution rule is specified.
- The no-scene/single-scene path must remain behaviorally identical and avoid
  meaningful extra work.
- Scene disconnect must not be treated as application termination.

## Causal attribution boundary for asynchronous work

A scene can be selected automatically only while trustworthy provenance still
exists. A `UIView` reached from a `UIEvent` can identify its `UIWindowScene`.
Customer work invoked synchronously during that event can therefore receive an
internal opaque scene token. A structured `Task {}` created inside that dynamic
scope inherits the token through `TaskLocal`, including across suspension. A real
three-minute URLSession probe now validates that inheritance after another scene
becomes representative. This does not extend to schedulers that discard task-local
context.

The following paths have no generally reliable automatic scene owner and must be
documented as ambiguous unless an application supplies one:

- `Task.detached`, `DispatchQueue.async`, timers, and pre-created tasks resumed
  later;
- shared repositories, caches, background workers, global prefetching, push, and
  background refresh;
- framework-created tasks and observers whose execution context is not inherited;
- scene connection or `viewDidAppear` work without a scoped callback;
- a request shared or coalesced by multiple scenes.

SwiftUI outer `.onAppear` and the synchronous prefix of `.task` are not UI-event
handoff contexts and still invoke before the inner RUM modifier's appearance
callback. Attachment-only, `willMove(toWindow:)`, and child-controller experiments
therefore misattributed them to the preceding view. On iOS 17+, the later
trait-backed explicit-tracking path gave the RUM queue enough scene-aware state to
attribute all tested lifecycle actions and resources to the destination view.
That is backend-validated semantic behavior, not TaskLocal inheritance or a
guarantee about observable callback/view-command ordering. Transparent automatic
SwiftUI tracking is now backend-proven to fail in the native lifecycle as well as
the UIKit-hosted probe.

Thread-local storage is only a synchronous bridge around event dispatch. Thread
identity must never be interpreted as asynchronous scene ownership. The SDK must
not infer an owner from `keyWindow`, the foreground scene, the last active scene,
or the process-representative `RUMCoreContext`, and it must not duplicate one
operation into every active scene.

When provenance does exist, the intended internal Resource/Trace contract is:

1. Propagate an opaque scene token, not a permanently frozen global RUM context.
2. Resolve that scene's fresh session, view, and valid action at the actual
   request or span start.
3. Freeze that one selection for metrics, completion, errors, RUM Resource, and
   Trace writing, even if navigation, session rollover, or scene closure follows.
4. Make RUM Resource and Trace consume the same start-time selection so their
   correlation cannot disagree.
5. Fail closed when an explicit source scene has no valid context; never resurrect
   another scene's representative context.

For work with no provenance, the process-representative fallback is the chosen
compatibility behavior, not exact attribution. It preserves existing event volume
and avoids introducing a resolver requirement, while accepting that source-less
work may be attributed to the wrong concurrent scene.

## Gap and evidence matrix

| Area | Baseline risk | Source evidence | Simulator evidence | Backend evidence | Status |
| --- | --- | --- | --- | --- | --- |
| UIKit view lifetime | A view in one scene stops a still-visible view in another | Baseline global stack; branch scene-keyed stacks/scopes | Fixed run opened B without stopping A | Both scene view IDs coexist in one session | Fixed in branch; tests and runtime pass |
| UIKit navigation | Navigation histories from all scenes interleave | Baseline global stack; branch isolates navigation per scene | Pushes, duplicate-name views, modal presentation/dismissal, and scene closure affected only the source window | Independent A/B view chains and IDs persisted | Fixed in branch; tests and runtime pass |
| Explicit SwiftUI view lifetime | Modifier identities can collide, detach can retain stale scene state, and synchronous lifecycle work can precede the RUM start | Branch resolves the hosting scene only for declared multi-scene apps, keeps stable lifecycle identity, ignores transient detach, and on iOS 17+ bridges a scene custom trait into SwiftUI; `willMove(toWindow:)`, child-controller, and trait lifecycle hooks were all tested | Trait-backed `onChange(initial:)` reduced the outer-callback gap from 35 ms to 2-3 ms without duplicate views; four synchronous lifecycle actions and six resources all resolved to their intended new views despite earlier invocation | Backend view/action/resource IDs confirm the earlier misattribution, the removed duplicate, and correct semantic attribution in both trait runs plus the synchronous-action run | Explicit `.trackRUMView` semantic attribution passes; view-before-callback ordering is not guaranteed |
| Automatic SwiftUI view lifetime | Transparent hosting-controller discovery can select a process-global history, run after lifecycle work, or miss native scene transitions | Core routing accepts a discovered controller's scene identity; both probes use `DefaultSwiftUIRUMViewsPredicate` without explicit modifiers. iOS 27 no longer matches `content.list.item.type`; `elements.body.viewType` is a destination registration rather than current-screen identity | UIKit-hosted and native runs put lifecycle work on preceding views. LLDB shows root/base and hosting-controller appearance boundaries do not expose a usable semantic view before Home/Detail `.onAppear`; native scene B initially reused scene A Detail | Sessions `ae9530b4-4117-4895-a1fe-7442a160e76f`, `721dcd8f-c88c-44f8-be1b-99d60829da92`, and `ffe3a564-c484-4d2a-b1c7-1e7170d333d0` confirm wrong exact IDs, late destinations, and the B-to-A mapping | P0 semantic failure reproduced; transparent title/reflection/lifecycle candidates are rejected, and a reviewed explicit integration is next |
| SwiftUI navigation | Hosting controllers from all windows share one active history, and transparent discovery may report container transitions instead of customer screens | Scene-keyed scope support resolves explicit modifiers and automatic hosting controllers by scene; the native harness uses a bound typed `NavigationStack` | Manually tracked concurrent stacks, duplicate-name destinations, and modals pass. Native automatic Home is absent and every Detail lifecycle phase stays on the source navigation host before the final destination appears | Manual source-scene chains remain independent; native single/two-window sessions retain all lifecycle events on the wrong preceding views | Manual core path passes; automatic root/destination creation fails; `NavigationSplitView` and restoration pending |
| Tap actions | Touch window is available but not propagated to RUM scope routing | Branch retains the touch/modifier scene; new actions no longer fan out to older scene action scopes | UIKit and SwiftUI source-window taps, navigation links, duplicate-name controls, fixed-toolbar activation, and close actions passed | Actions emitted once on their originating view; the pre-fix manual B fan-out did not recur | Core path passes; filtered physical interaction followed by a later source-less API remains open |
| Scroll actions | Scroll callbacks have a view/window but no scene reaches the command | Branch retains source scene through drag and deceleration | SwiftUI scene D swipe emitted on D while another scene survived; UIKit scroll/deceleration remains to be repeated | SwiftUI D action retained D view | SwiftUI runtime passes; UIKit matrix remains open; focused tests pass |
| Resources and traces | A generic request/span has no intrinsic scene; representative fallback can be wrong | Branch has an experimental `sendEvent`/TaskLocal causal bridge, synchronous owner capture, and frozen completion routing; GCD, detached, timer, repository, lifecycle, and shared work remain ambiguous | Structured tasks and UI-local work retain source ownership; detached/GCD/timer and early scene lifecycle use the representative. Delayed UIKit/SwiftUI resources and traces survive source-scene closure | RUM and APM agree on the boundary; teardown traces `6aa50f23000000001829c0dfb272bbb9` and `6aa5128c0000000048ed46829eb03478` retained their source scenes | Partial and bounded; known provenance and completion routing pass, while generic source discovery remains impossible |
| Manual errors and process-wide long tasks | Source-less APIs/signals have no unique scene | Branch uses one process representative; no broadcast | Pending | Pending | Explicit fallback policy; not source-attributed |
| Logs and mirrored errors | A log and its later RUM error can resolve different global views | Branch snapshots request-local RUM context and preserves exact or same-scene routing for the mirrored error; legacy no-scene work retains representative fallback | Pending fixed-runtime rerun | Pending fixed-runtime rerun | Captured-view mirroring fixed and unit-validated; targeted two-window runtime proof remains open |
| Vitals, TNS, and INV | Process vitals overlap; navigation edges could cross scenes | Branch has one INV tracker per scene; TNS follows resource owner; vitals remain process-derived per view | Pending | Pending | INV/TNS fixed; vitals policy and external displays remain partial |
| Feature operations and flags | Delayed steps receive the global active view; string-concatenated identities can collide in both RUM and Profiling; permanently pinning later steps to the start scene would misrepresent cross-window work; closing the last proven view can drop an end step | Branch uses typed `(name, key)` identity in RUM and Profiling, independently resolves each step, refreshes a last-proven view snapshot only from trustworthy context, and uses that snapshot before representative fallback | Focused tests cover A-to-B success/failure, A1-to-A2 navigation, parallel keys, reverse completion, explicit/inferred override, duplicate starts, teardown, and profiler key collisions; post-fix scene D runtime emitted both steps after D closed | Reducer produced a successful operation keyed `206E691E-33AC-4BF1-8D26-E48D81315D9A` with identical closed-scene start/end view; live A-to-B backend proof is pending | Internal lifecycle, attribution, and Profiling identity contract implemented; public target API and live cross-window/duplicate proof pending; flags remain open |
| Session rollover | A process-wide stop/expiry can lose still-visible views or revive the view being replaced | Branch snapshots every active foreground scene and now restores only branches unaffected by a scene-targeted start/stop | Explicit stop followed by B Home -> Detail initially dropped A; fixed rerun emits new A Home and B Detail views | New explicit-stop session contains both raw view documents and the delayed B request remains on B Detail; reducer converged to `view.count:2` | Fixed for explicit stop, inactivity, and max duration; product UI rendering of overlap remains unchecked |
| Session Replay | Recorder/context mapping may follow an arbitrary scene's key window | First key window across an unordered scene set; one coordinator | Repeated two-window UIKit/SwiftUI runs, navigation, and scene teardown completed without an SDK crash | Replay was available on the broad and post-fix sessions | Out of scope except crash safety; coexistence requirement passes for the exercised matrix |
| WebView correlation | Browser events can be stitched to another scene's native container | Branch carries private source-scene metadata and queries scene-keyed view history | Pending fixed-runtime rerun | Pending | Fixed in branch; three focused tests pass |
| Profiling | Profile-level RUM attributes are last-writer-wins across views | One mutable correlation snapshot | Pending | Pending | Confirmed by source |
| Crash/fatal context | Any view update can overwrite one process crash context | Branch restricts updates to the representative and restores another active scene when needed | Pending | Pending | Fixed to representative policy; focused tests pass |
| App/scene lifecycle | Per-scene transitions are invisible to view ownership | Branch observes background, foreground, and disconnect per scene | Requesting UIKit and SwiftUI scene destruction stopped only the source views and surviving scenes continued | Destroyed-scene views became inactive without replacing the survivor | Scene close/destruction passes; temporary disconnect, reconnect/restoration, and per-scene background/foreground remain open |

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
- Preserve the automatic SwiftUI mode and session
  `ae9530b4-4117-4895-a1fe-7442a160e76f` as the failing baseline. Separate two
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
- Keep the rejected iOS 27 `viewIsAppearing` run
  `13e39eae-ccc8-47a6-8125-3f52fab589b8` in the experiment ledger. The callback
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
the Operations proposal below as the review starting point, retain the existing APIs and
their inferred behavior, and do not expose internal RUM view UUIDs. Resolve UIKit
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
- Update this assessment with exact supported, partial, ambiguous, and unsupported
  surfaces before proposing a release contract.

## Confirmed product decisions

1. Generic work with no trustworthy source uses the process representative,
   intended to be the last-interacted view. It emits once and is never broadcast.
   This compatibility fallback can be inaccurate and must not be presented as
   exact ownership.
2. Entering the background ends only that scene's visible view; foregrounding
   restarts it. Merely losing focus while remaining visible does not end a view.
3. Concurrent scene views overlap within one application RUM session. Scene
   identity remains internal and is not added to the intake schema.
4. Process-wide long tasks, hangs, memory warnings, and crashes emit once on the
   process representative. Shared process/render-loop vitals are not duplicated
   as independent per-window measurements.
5. Session Replay needs crash-free coexistence only. Scene-correct recording,
   touch routing, and replay context are out of scope for this project.
6. iPhone Duo on iOS 27.1 is the release target. Semantic multi-scene support on
   iOS 15/16 is not required, while normal apps on every supported deployment
   target must remain compatible.
7. On the supported OS range, SwiftUI lifecycle work must belong to the intended
   RUM view. The contract is semantic attribution, not observable ordering between
   customer callbacks and internal command or payload emission. Unsupported
   SwiftUI internals are not an acceptable fix.
8. Resource and Trace work is limited to preserving trustworthy provenance and a
   shared frozen owner. The SDK does not guess after causality is lost and does
   not defend developer-written handlers that rewrite a request across automatic
   capture or first-party header-injection boundaries.
9. Operations use exact application-wide `(name, operationKey)` identity; scenes
   never namespace it. Every step resolves its view independently. A last-proven
   snapshot is a fallback, not permanent ownership by the start scene.
10. Starting the same Operation identity twice tracks only the latest start in
    the client. A later success or failure ends only that instance; the earlier
    backend operation remains open until its four-hour timeout. The SDK emits no
    synthetic end. Customers must use a unique key for every concurrent instance.
11. The Operation view-target escape hatch requires normal Swift, Objective-C,
    protocol-compatibility, and RFC review. Existing APIs retain inferred behavior,
    and no internal RUM view UUID becomes public.

## RUM Operations contract and API review proposal

The implemented internal contract is:

1. Resolve every start, update, retry, success, and failure independently.
2. Prefer an explicit customer target, then a reliably inferred call-site view
   and scene, then the operation's last-proven view snapshot, then the existing
   process representative for compatibility.
3. Whenever an explicit or reliably inferred target resolves a live tracked view,
   refresh the operation's retained snapshot with that view. A process-
   representative fallback is not proof and must not overwrite the snapshot.
4. Use exact `(name, operationKey)` identity across every scene. Two independent
   instances with the same name need different opaque keys.
5. On a duplicate start, emit both starts as requested, replace only the SDK's
   locally tracked latest instance, and emit no client-side end. A later success
   or failure ends that latest instance. The earlier backend operation remains
   open until its four-hour timeout.

The internal routing and warning changes are implemented. The public escape hatch
is deliberately not implemented until API review because it changes the SDK
surface and needs Swift, Objective-C, and protocol-conformance compatibility
decisions. A value-type proposal that does not expose internal RUM UUIDs is:

```swift
public struct RUMOperationViewTarget {
    public static let inferred: Self

    @MainActor
    public static func current(in scene: UIWindowScene) -> Self

    @MainActor
    public static func tracked(key: String, in scene: UIWindowScene) -> Self

    @MainActor
    public static func tracked(_ viewController: UIViewController) -> Self
}
```

The current APIs would remain unchanged. New overloads would add a `view` argument
to `startOperation`, `succeedOperation`, and `failOperation`; any future public
update or retry API must add the same targeting capability. For example:

```swift
rum.startOperation(
    name: "thread_open",
    operationKey: operationKey,
    view: .current(in: sceneA)
)

rum.succeedOperation(
    name: "thread_open",
    operationKey: operationKey,
    view: .current(in: sceneB)
)
```

The `view` argument must remain required on these overloads so it does not become
ambiguous with the existing convenience methods. The SDK should synchronously
turn UIKit objects into opaque values before enqueueing the command: a scene's
persistent identifier, a manual `ViewIdentifier.key`, or a controller's
`ObjectIdentifier`. It must not retain UIKit objects on the RUM queue.
`current(in:)` resolves the current tracked view in the given scene.
`tracked(key:in:)` matches a manually tracked key inside that scene, and
`tracked(_:)` matches the tracked controller instance.

The command must preserve the explicit target separately from its independently
captured call-site inference. Collapsing both into the existing `command.target`
would skip precedence level 2 whenever an explicit target cannot resolve. Session
processing must resolve the explicit candidate first, then the inferred candidate;
only a candidate that resolves to a live tracked view is trustworthy. The manager
then applies its retained snapshot and process-representative fallbacks. Supporting
the exact-view forms requires an internal logical target keyed by `ViewIdentifier`
plus a scene where the identity is not globally unique, never a public RUM UUID.

To avoid making a new requirement on every external `RUMMonitorProtocol`
conformer, review should use extension-only overloads backed by a private targeting
capability, with the existing inferred method called exactly once for custom
conformers and the NOP monitor. The Objective-C surface needs a
`DDRUMOperationViewTarget` companion with `inferred`, `currentInScene:`,
`trackedViewWithKey:inScene:`, and `trackedViewController:` factories. Use the
repository's existing non-watchOS UIKit availability convention rather than
gating the API to iOS 27; `UIWindowScene` predates the SDK's iOS 15 minimum.

One prerequisite remains: the public `startView(key:)` API cannot explicitly bind
that manual key to a scene. A keyed target is deterministic only if the view
already received scene ownership through internal/SwiftUI tracking. API review
must therefore include scene-targeted manual keyed-view start/stop overloads, or
drop the keyed target until that ownership can be established safely.

Customer documentation shipped with that API must state that scenes do not
disambiguate Operations automatically. For a cross-window Operation:

1. Generate one opaque operation key.
2. Start the Operation in scene A.
3. Pass the key to scene B through application window-routing state or
   `NSUserActivity`.
4. Complete it in scene B with the exact same name and key.
5. Explicitly provide the start/end view when call-site inference is unavailable.

Independent loads in identical windows must use distinct identities, for example
`feed_load/key-A-1` and `feed_load/key-B-1`. Reusing a key, or omitting it for
concurrent same-name work, can leave the earlier Operation open until the four-
hour backend timeout.

Required test coverage is tracked explicitly:

| Required case | Current coverage | Status |
| --- | --- | --- |
| Start in A, succeed in B | Manager and session-scope start/end view assertions | Focused pass; live backend pending |
| Start in A, fail in B | Manager start/end view and failure-reason assertions | Focused pass; live backend pending |
| Start in A1, navigate in A, end in A2 | Manager and session-scope navigation assertions | Focused pass |
| Parallel A/B, same name, different keys | Manager identity and view sequence | Focused pass |
| Reverse-order completion | Manager identity and view sequence | Focused pass |
| Explicit target overrides wrong representative | Session-scope internal scene-target regression | Internal pass; public overload test pending API review |
| Trustworthy inferred B overrides stored A | Manager scene-B step regression, including update/retry snapshot refresh | Focused pass |
| Closed origin with no new context uses snapshot | Manager vital/message retained-view assertions plus backend teardown run | Focused and backend pass |
| Closed origin then explicit B completion uses B | Manager exact-view assertion | Internal pass; public overload test pending API review |
| Duplicate identity has corrected warning and no synthetic end | Manager warning plus exact `[start, start, end]` step sequence, with both a reused key and omitted key | Focused pass; live warning/raw-vital proof pending |
| Existing single-scene and source-less behavior | Representative-change and legacy no-view regressions | Focused pass; full 1,033-test RUM suite passes |

API review must settle the public type/name and the scene-targeted keyed-view
prerequisite. The requested application-wide identity means that scenes do not
namespace an Operation; it does not add a new cross-session persistence contract.
The manager and its retained view snapshot remain session-local, while duplicate
starts follow the explicitly requested four-hour orphan-timeout warning. Any
change to cross-session Operation semantics is separate backend/product work and
does not block the multi-scene implementation. Emitted steps remain best-effort
and are never rejected only because local tracking state is absent.

## Open product questions from the goal review

- Which reviewed SwiftUI integration should supply semantic root and destination
  identity before lifecycle work on iOS 27: a bound navigation/root wrapper, a
  narrower explicit tracking contract, or another supported Apple API boundary?
  The transparent controller/title/reflection candidates tested so far are
  disproven, and adding public API requires RFC review.
- Should the Operation target review include scene-aware manual keyed-view
  start/stop so `.tracked(key:in:)` is deterministic, or should that target form
  be deferred? The current public `startView(key:)` cannot explicitly establish
  scene ownership.
- For `NavigationSplitView` or `UISplitViewController`, does “proper view” mean one
  current destination/detail view per scene, or separate simultaneously active RUM
  views for visible panes? The current architecture intentionally supports one
  active view branch per scene, so the latter would be a separate model change.
- Is correct event-to-view attribution inside one RUM session sufficient product
  representation for parallel window histories, or must the RUM product visibly
  distinguish window branches? Raw intake and the reducer accept overlap, but no
  scene identifier is serialized and product UI presentation has not been reviewed.

## Experiment log

### 2026-09-11 — Baseline and tooling

- Confirmed Xcode 27.0 and a booted iOS 27.0 iPad simulator.
- Connected to Xcode's tool server through `xcrun mcpbridge`; workspace, schemes,
  destinations, build, run, console, test, and device-interaction tools are
  available.
- Confirmed Datadog RUM backend search/aggregation access is available.
- Confirmed the integration host opts out of multiple scenes and the Example host
  has no scene manifest.
- Confirmed current branch and preserved pre-existing project/local-config edits.
- Built the unmodified `Example` scheme successfully for the iOS 27.0 iPad.
- The control app was then terminated at launch by UIKit with:
  `Application failed to launch: UIScene life cycle is required for apps built
  with this SDK.` This is a probe-host compatibility failure, not yet evidence
  about RUM event attribution. The Example target must adopt scenes before it can
  be used for the experiment.
- The first attempt to prepare the isolated `IntegrationTests` runner with
  `make ui-test-podinstall` failed before CocoaPods ran because the repository's
  locked Ruby gems are not installed (`Bundler::GemNotFound`, including
  CocoaPods 1.15.2). No Pods or project files were produced by this attempt.
- Installed the repository-locked Bundler 2.5.21 and CocoaPods 1.15.2 bundle,
  then generated `IntegrationTests/IntegrationTests.xcworkspace` successfully.
- The unmodified generated Pods project then failed to build with Xcode 27
  because 21 build configurations from transitive pod targets declare iOS 12,
  while this Xcode supports simulator deployment targets from iOS 15. For the
  experiment only, the ignored generated `Pods.xcodeproj` was mechanically
  raised to the repository's existing iOS 15 minimum. This must be reapplied
  after `pod install` unless a reviewed Podfile/toolchain fix replaces it.
- The existing `Runner iOS` scheme in its `Integration` configuration then
  failed because the Runner imports `DatadogTrace` with explicit modules while
  that local module was built without `-enable-testing`. A dedicated shared
  `RUM MultiScene Probe` scheme now uses the Debug build and launch
  configurations and built successfully on the iOS 27 iPad before probe sources
  were added. Keep this scheme isolated from the normal integration-test matrix.
- Enabled `UIApplicationSupportsMultipleScenes` in the integration Runner and
  added an optional programmatic root-controller hook to `TestScenario`. The
  default implementation returns `nil`, so existing storyboard scenarios retain
  their current launch path.
- Added a scene-aware RUM probe scenario with independently labelled UIKit and
  SwiftUI navigation, duplicate-name views, modal transitions, automatic and
  manual actions, and delayed resource, trace, and feature-operation controls.
  Every control records the native scene-session identifier and an independent
  source-scene marker; only the run identifier is installed as a global RUM
  attribute. This separation is essential for detecting wrong SDK attribution.
- Payload mappers now print compact view/action/resource/error/long-task records
  with their resulting RUM view identifier and name. At this checkpoint the next
  gate was compilation and backend correlation; both were completed by the later
  runs below.
- The complete UIKit and SwiftUI probe built successfully with Xcode's project
  build action in 7.475 seconds and launched on the target iPad. The first live
  control run is `a9fab1c4-5cb6-4468-9d1a-dc0936116c46`; it created RUM session
  `18e48c14-7073-4353-9b85-0121b93c74e0` and native scene session
  `82E7F28F-E381-4FC3-B9FB-4FAB11809C13` for scene A.
- Console payloads show the expected single-window control transition from
  `ApplicationLaunch` (`0c7b7745-8546-433a-90ca-e9271c0bd010`) to
  `UIKit scene-A Home` (`5c8e6e7f-0c44-4307-946d-5c8cb5886140`). This proves
  the harness is instrumented; it is not evidence of concurrent correctness.
- Datadog intake returned seven initial events for that exact run and session,
  including both views, three long tasks, the session event, and the app-launch
  vital. Detailed events preserve `context.probe.run_id`; scene-A view-derived
  events also preserve `context.probe.source_scene` and the native scene-session
  identifier. Backend connectivity and marker round-tripping are therefore
  validated before opening a second window.
- The reproducible backend query is
  `@context.probe.run_id:<run-id>`. The shorter `@probe.run_id:<run-id>` returned
  no results because custom RUM attributes are indexed below `context`.
- Concurrent simulator-flow and backend-attribution claims remain pending until
  the two-window interaction sequence completes.
- The first `Open another window` control was delivered at 11:35:08 local time.
  SpringBoard created a second application scene and began arranging the new and
  existing scenes in a half-and-half layout. At approximately 11:35:10,
  simulator `backboardd` respawned; RunningBoard then killed probe PID 94704 with
  reason `backboardd respawn` / `SIGKILL`, followed by a SpringBoard restart.
  This is a simulator-system interruption, not an application or SDK crash. The
  run ended before any scene-B RUM payload could be observed. Retry once with the
  same explicit run marker; if it repeats, treat the iOS 27 window-manager path
  as an environment blocker and use a less aggressive window arrangement while
  preserving two connected scenes.
- Relaunched with the same run marker. The new process created RUM session
  `5fc61f1f-9253-4c12-9917-d1568e4ca9d5` and scene-A native session
  `D141101B-5822-4CDC-BE73-713885B62DF3`.
- The second open-window attempt reproduced the simulator-system failure, but
  captured the critical unchanged-SDK sequence first: scene B connected with a
  distinct native scene session, both application scenes entered SpringBoard's
  multi-window layout, RUM emitted scene-A Home with `active=false`, and only
  then started `UIKit scene-B Home` with view ID
  `0fcf2aa2-313e-4157-b3dd-27ab577e57dc` and `active=true` in the same RUM
  session. That attempt's native scene-B session was
  `1BD5DCB9-0024-4115-9055-1A24027C00A2`. Scene A had not been closed. This is
  direct evidence that the process-global view stack incorrectly models
  concurrent scene creation as navigation away from A.
- The second interruption again killed the app, SpringBoard, InputUI, and other
  simulator UI processes with `OS_REASON_RUNNINGBOARD` after a `backboardd`
  respawn. Repetition makes this an iOS 27 simulator/window-manager constraint;
  one final retry may avoid Xcode's post-tap XCTest snapshot by using Device Hub
  directly. Further identical retries are not useful.
- A final Device Hub/CUA-controlled attempt temporarily held scene A
  (`D141101B-5822-4CDC-BE73-713885B62DF3`) and a new scene B
  (`7B2E694F-A3B0-48DB-945A-4B51FB35D4FA`) visibly side by side. The next
  accessibility refresh coincided with a third global `backboardd` respawn at
  11:48:24. It killed the app (PID 5055), SpringBoard, InputUI, widgets, and
  other simulator UI processes before alternating A/B controls could be sent.
  The third system-wide reproduction means both Xcode interaction and direct
  Device Hub/CUA paths are unstable on this simulator image.
- The CUA relaunch reached backend RUM session
  `86a1a492-24db-485c-80dc-1a4a21dab1e7`, with scene-A view
  `9ea7f2f3-40ba-4638-8fe8-a0ed8804ff25`. Scene B was killed before upload.
  The prior console run remains the complete concurrent-view evidence, with
  scene-A view `ea085412-f0a1-4425-b830-7bf67184bf57` and scene-B view
  `0fcf2aa2-313e-4157-b3dd-27ab577e57dc`.
- Began the proactive core fix after preserving the unchanged-SDK evidence.
  Current edits keep one session, track one active view branch per scene, target
  automatic UIKit navigation and touch commands at their source scene, retain a
  process-representative compatibility path, and reserve intentional broadcast
  for lifecycle/session-stop commands. Focused handler tests now cover concurrent
  scene starts and navigation in A while B remains open. After adding the legacy
  SwiftUI handler overload required by the existing internal protocol, the full
  `RUM MultiScene Probe` scheme built successfully through Xcode in 9.566 seconds.
  Seven focused `DatadogRUM` tests then passed through Xcode: concurrent handler
  starts, navigation isolated to one handler stack, two simultaneously active
  session view branches, navigation isolated to one session branch, a targeted
  action attributed once to the earlier scene, an unscoped action emitted only
  once through the representative branch, and session stop closing all branches.
  The edits remain experimental until lifecycle/session-rollover coverage,
  broader regression, and fixed-runtime attribution pass.
- Extended the action path beyond taps: continuous scroll/swipe commands now
  retain the source scene from gesture start through deceleration and completion.
  Automatic UIKit/SwiftUI taps, manual SwiftUI taps, and manual SwiftUI views
  also carry a scene target; a hidden non-interactive SwiftUI representable reads
  the hosting `UIWindowScene` without changing public API. Four focused action
  and modifier tests pass, including the legacy unscoped fallbacks.
- Added scene lifecycle observation. `UIScene.didEnterBackgroundNotification`
  suspends only that scene's visible view, `willEnterForeground` restarts only
  that branch, and disconnect stops/removes only that scene. Application-level
  notifications remain the process lifecycle signal and fallback for views whose
  scene cannot be resolved; idempotent stack state prevents duplicate stops when
  scene and application background notifications both arrive. Three lifecycle
  tests pass, including the existing legacy application-background regression.
- Session continuity is now multi-scene-aware. Maximum-duration/inactivity
  refresh and explicit stop/restart retain every active foreground scene view,
  assign each a new view ID in the new session, preserve the representative
  scene, and route the triggering action to its scene. New concurrent expiration
  and explicit-restart tests pass alongside the existing single-view tests.
- Interaction-to-next-view state is now isolated per scene. A focused test proves
  that A1 -> action A -> A2 remains one INV history while concurrently visible B
  receives neither A's action nor A2 as its successor; the legacy no-scene path
  keeps its existing tracker.
- The first URLSession experiment snapshots whichever view selection is available
  during request modification and retains that exact internal target through
  start, metrics, response, and error callbacks. The per-task target map is locked
  and removed on completion. Four handler tests cover success, error, reverse
  completion, and legacy fallback; a scope test proves that an already-correct
  scene-A selection does not migrate to B. These tests validate owner freezing,
  not source discovery. A plain exported representative view does not prove that
  A originated the request.
- Error logs mirrored into RUM now carry the same captured RUM view ID as the log
  across the asynchronous feature-message bus. RUM removes this private routing
  metadata before event encoding and targets the exact still-active view. Sender
  and receiver tests pass with two concurrent scene branches. If asynchronous
  delivery outlives the captured view, routing may move only to a newer active
  view in the same scene. If the captured scene is gone while another survives,
  the mirrored error is dropped rather than crossing scenes. Only legacy no-scene
  work retains representative fallback. Resource completion separately retains
  its cached owner. This aligns the log and mirrored RUM error without silently
  misattributing a delayed error to another window.
- Manual and OpenTelemetry spans freeze the RUM context selected at span creation,
  but the process-wide exported context is not necessarily their originating
  scene. Trace-only URLSession spans are created at completion with an earlier
  start timestamp, so the experiment captures a request-start selection and
  supplies it to the late writer. Four Trace tests prove that supplied A/B
  selections survive reverse completion and later representative changes. They
  do not prove that a generic request automatically selected A or B correctly.
  Requests tracked as RUM resources still avoid duplicate client spans as before.
- The first feature-operation routing experiment remembered the scene that owned
  the start and resolved every later step against that scene's current view. It
  fixed A1 -> A2 navigation while B was process-representative, and used the same
  selected view for the vital, containing view update, and profiling message.
  Local tracking also moved from string concatenation to a typed `(name, key)`
  identity; formerly colliding pairs remained independent. The permanent start-
  scene rule was later rejected because a legitimate operation may start in A and
  finish in B. The typed application-wide identity remains. Identical `(name,
  key)` starts are never silently rewritten with scene identity; the latest start
  replaces local tracking and the earlier backend operation times out after four
  hours unless customers use unique keys.
- The first profiling-message assertion exposed that feature-operation profiling
  unnecessarily traversed an active view's unowned parent. Random legacy test
  fixtures could therefore crash when operation options requested RUM context.
  `RUMFeatureOperationManager` now derives application/session context from its
  own retained parent and overlays only the selected view ID/name. The four
  previously failing operation tests pass. After adding the later action-routing
  regression, the full RUM suite passes 964/964.
- Duplicate SwiftUI identities exposed a remaining asymmetry: scene identity was
  retained for `onAppear` but discarded for `onDisappear`, so the first matching
  stack could be stopped. The modifier now supplies the same captured scene on
  disappearance, and the handler restricts removal to that scene. Handler- and
  session-level tests prove two scenes can use the same identity and stopping A
  leaves B active.
- WebView RUM events now retain the scene of the exact `WKWebView` delivered by
  `WKScriptMessage`. The bridge adds a private message-bus marker, RUM removes it
  before encoding, and `ViewCache` keeps scene identity with each native view. A
  browser event from A therefore selects A's historical replay-enabled container
  even when B has the newer native view. Bridge, cache, and receiver tests pass;
  no public or intake schema changed.
- Fatal/crash context now follows the single representative active view instead
  of whichever concurrent scope happened to emit the last update. Non-
  representative resource updates cannot clobber it, and stopping the
  representative scene restores the still-active scene's latest full view state.
  Five focused new and legacy fatal-context tests pass. Crashes and fatal hangs
  remain process-wide single events by policy.
- Feature-flag payloads contain only flag key and value, so neither the SDK nor an
  integration receiver can recover a source scene after asynchronous delivery.
  Adding deterministic attribution requires a new context-bearing internal
  payload contract or scene-scoped API; current behavior remains representative.
- Main-run-loop long tasks, app hangs, and memory warnings have no intrinsic
  window owner. Broadcasting them would inflate counts. They remain single events
  on the representative view pending a different product policy.
- Concurrent same-display views each summarize the shared process CPU/memory and
  render-loop samples. INV is now scene-isolated and TNS follows resource
  ownership, but refresh normalization still uses `UIScreen.main`; external-
  display windows are therefore not fully supported by the vital path.
- Session Replay remains a known limitation for end-to-end multi-window replay: both
  recorders select the first key window across an unordered connected-scene set
  while consuming one representative RUM context. Touch buffering and layer/view
  snapshot state are also singular. A safe fix requires a scene-keyed recorder or
  multiplexor, not a different arbitrary-window heuristic. That semantic work is
  out of scope here; only crash-free coexistence gates the base-RUM work.
- Profiling correctly remains one process profiler, and feature-operation messages
  now carry the operation's selected scene view. A profile covering events from
  several windows still has last-writer-wins top-level RUM attributes, however;
  aggregation needs a backend-compatible correlation contract before changing it.
- Unscoped manual `startView(key:)` now joins/replaces the representative scene
  rather than creating a third scene-less branch. An unscoped stop for a detached
  `UIViewController` searches active identities across scenes, so it still stops
  its original branch after another scene becomes representative.
- SwiftUI manual view modifiers use a reference-backed hidden scene reader. The
  first implementation waited for `didMoveToWindow`, stopped only a view it had
  actually started, and reused the captured scene on disappearance. Later runtime
  evidence below disproved the assumption that attachment necessarily precedes
  customer `onAppear` work; do not treat this checkpoint as the final ordering
  contract.
- Broad module regression results after the core changes: DatadogRUM 964/964,
  DatadogLogs 89/89, DatadogTrace 142/142, and DatadogWebViewTracking 31/31.
  DatadogSessionReplay on iOS 26.5 produced 738 passes, 3 skips, and one unrelated
  failure where UIKit did not create the private `_UIScrollPocket` used by the
  test. On iOS 27 its Example-based test host was terminated by UIKit because that
  host has not adopted the required scene lifecycle; that is a host/toolchain
  compatibility issue, not a Session Replay SDK crash. Crash-free coexistence in
  the actual two-window probe remains the relevant runtime gate.
- The first fixed iPadOS 26.5 two-window run was
  `574be7dd-4482-48e5-b4cc-eaaa332179bd`, RUM session
  `59a3329e-1a21-486c-9ee5-190d111bfbf3`. Scene A Home used view
  `62209d98-78d2-45a2-a650-ba3adea0bd4e`; opening scene B created Home view
  `f5a8f052-653b-4303-9aad-9e09dd6f3802` without an inactive update for A.
  UIKit taps and the Home -> Detail transition were attributed only to B, with
  Detail view `b4b49f9b-2f28-4605-be76-5b5b97fd062b`.
- In that run, a 3-second resource, manual span, and feature operation started on
  B Detail 1, then B navigated to Shared Detail
  (`57237c78-2126-434f-881b-5adeee1325ab`) before completion. Backend intake
  stored the resource once on Detail 1. The span matched
  `_dd.view.id:b4b49f9b-2f28-4605-be76-5b5b97fd062b` once and matched the Shared
  Detail ID zero times. The operation's reduced event reports Detail 1 as
  `start_view` and Shared Detail as `end_view`.
- The same run exposed a new overlapping-action defect. While scene A still held
  the automatic action for opening B, source-less `addAction(.custom)` from B was
  propagated both to the representative view and to every view with an older
  action scope. Backend intake stored two `manual-action-scene-B` events: one on
  A Home and one on B Detail 1. Routing now fans out only
  `RUMStopUserActionCommand`; new start/add commands select one target. A focused
  regression test reproduces the overlap and passes.
- The rebuilt live verification run is
  `4d7dc23b-721d-4038-8c89-3b29a1c373c9`, RUM session
  `0caa932a-7c4c-4c9d-9fb5-4acb691118f9`. It retained A Home
  (`da5d853a-ce31-409a-b0aa-f1d738870998`) while opening B Home
  (`4fff5481-a693-4ff3-8505-c4a1a23953d2`). The same manual B action now appears
  exactly once in console and backend, attached to B Home. Switching only B to
  SwiftUI created Home `85c8dea1-4fbc-44b0-8980-0ccce59a0d7f`, then
  `NavigationStack` created Detail 1
  `25038ecf-e4c8-4fbb-ae34-ae81a18f1718`, without cross-scene view IDs.
- Device Hub control became unavailable when the host Mac locked during this run.
  Xcode console and Datadog intake remained available and the probe process was
  left running. Resume physical tap, scroll, modal, A/B switching, lifecycle, and
  Session Replay coexistence checks after unlocking; do not discard this session
  merely because GUI input paused.

### 2026-09-11 — Fixed-runtime and causal-context checkpoint

- A later iPadOS 26.5 two-window run used run
  `6a0b61d0-85a8-4915-b02e-63ab53fa13db` and RUM session
  `2b282934-aae9-4495-b7fc-797736f58735`. It kept scene A UIKit Home
  (`40e6dda1-67ef-4d67-b770-0e5ec8a132a4`) active while scene B opened UIKit
  Home (`be5c0926-d927-4ce9-a39f-f6abccdc23d0`), then created scene B SwiftUI
  Home (`2516c6f7-41a8-4343-a5a1-e287cda95c75`). Session Replay uploads were
  accepted and no SDK crash occurred; no scene-correct Replay claim is made.
- The iPadOS 27 run `e7bf0f3e-2e46-4487-af4f-072cd7ba8ab8` produced RUM session
  `feb94679-4b2e-4821-8146-a531e8608672`. A physical SwiftUI navigation tap was
  attributed to its originating Home view and the resulting Detail view was
  correct. Opening the second window then crashed simulator `backboardd` in Metal
  validation (`invalid pixelFormat`), with no Datadog, Session Replay, or probe-app
  frames and backend `crash_count:0`. Do not repeat that iOS 27 compositor path;
  use iPadOS 26.5 for the complete two-window matrix until the simulator image is
  stable.
- The branch now has experimental synchronous UI-event context handoff,
  structured-Task propagation, request pre-start, captured owner maps, exact
  delayed-event routing, and third-party URLSession-handler compatibility changes.
  Build-for-testing succeeds. Twelve focused RUM tests and four focused
  DatadogInternal tests pass at this checkpoint; complete module regressions have
  not been rerun after the newest changes.
- Review found correctness risks before those mechanisms can be kept:
  `.view` routing is recomputed while scopes mutate; cached legacy ownership is
  conflated with unknown ownership; pending-action merging can revive another
  scene from an intentional nil or disagree with a rejected action; and a later
  custom URLSession handler can mutate an allowed pre-started request into a
  disallowed one, orphaning the resource.
- The two core-routing risks are now fixed independently of source discovery.
  Exact `.view` routing resolves one destination before any scope mutates, and
  `ViewCache` distinguishes scene-backed, known-legacy, and unknown ownership.
  Seven focused regressions pass, including a completion owned by inactive A1
  while A2 has an action: the resource remains on A1 and A2's action resource
  count remains zero. The pending-action and custom-handler risks remain open.
- The intentional-nil part of the pending-action risk is fixed. Logs and spans
  now require a captured source-scene context before merging a subsequently
  accepted action, so an explicit nil cannot acquire another scene's
  representative action. Both focused regressions pass. The complete Logs suite
  passes 95/95.
- The complete Trace run initially caught a single-scene compatibility regression:
  adding scene-aware RUM baggage made a customer request with existing tracing
  headers look like an SDK-created trace, changing which RUM session baggage won.
  The handler now distinguishes pre-existing Datadog, B3 multi, B3 single, and
  W3C `traceparent` contexts. SDK-created traces use the frozen request selection;
  pre-existing traces retain the former process-context behavior. All 147 Trace
  tests now pass.
- Product clarification established that generic Resource/Trace source discovery
  is impossible once causal provenance is lost. Further expansion is paused until
  the required real-URLSession experiment matrix determines which handoff pieces
  are necessary. The implementation plan above supersedes earlier statements that
  described automatic URLSession attribution as solved.
- Actual URLSession run `da902d8a-f16e-4fa9-b82c-8dcdbaa6dc5f` produced RUM
  session `5e65abff-6999-45b2-b8ca-cf199b1b13e4` on iPadOS 26.5. Scene A used
  native session `94F798B5-7D24-4990-80BC-EFB621257719`, ApplicationLaunch view
  `f4f2c0e7-c6db-4ae6-9c41-5acacb5b1cf3`, and UIKit Home
  `1760e0e1-1fcd-4dfc-a5af-4a1f5a793917`. Scene B used native session
  `04A1C58A-6A9A-4387-9F7A-442BD29FE70A`, UIKit Home
  `6a5cc2ea-ab30-4f62-a6b8-28694dc80fd4`, and UIKit Detail 1
  `35107714-29c8-4cf6-9c53-23a34f94228f`.
- That run proves lifecycle work is not automatically scene-attributed. Intake
  stored scene A's connection request on ApplicationLaunch, but both scene B's
  connection request and scene B's Home `viewDidAppear` request on scene A Home.
  Scene B's own source markers survived, making the mismatch unambiguous. This is
  a correctness gap, not merely an unknown source in the test harness.
- Synchronous scene-B UIKit work was correctly frozen to B Home: request
  `0019d18e-4fad-441a-8439-0019762ec6e0` emitted resource
  `23df7b22-777c-4a51-a115-8ee852d1c6ef` and both its RUM Resource and APM span
  retained accepted action `45d48652-5e7f-4306-92c2-20833be6b94e`. A filtered
  action emitted the resource once on B Home with no action ID, as intended.
- A URLSession task created on B Home and resumed after navigating to B Detail 1
  resolved at resume/interception time rather than task-object creation time.
  Request `3d4bffbb-2cac-4cd0-92d4-309b1fde8591`, resource
  `ad079bd1-c1f6-4c53-a2f7-ae2990933811`, and its APM span all use Detail 1 and
  the resume tap action. This validates actual-start selection for the current
  session; session rollover before start remains a separate case.
- The first structured-task case waited 200 ms, beyond RUM's 100 ms discrete
  action timeout. Its missing action ID is therefore expected, not evidence of a
  handoff defect. The probe now separates a 20 ms suspended task that should
  retain the accepted action from a 200 ms post-expiry task that should not.
  Detached, GCD, and timer starts now wait three minutes so another scene can become
  representative before they start; the earlier run accidentally left B
  representative and could not prove their lack of provenance. A separate
  three-minute structured-Task control distinguishes inherited scene provenance
  from those source-less schedulers. A compound UIKit control also schedules
  structured work, stops the RUM session, navigates, and starts the request
  afterward. The updated probe builds successfully.
- Fresh run `8a71b04b-ee69-4670-bdb1-28a6a3625662`, initial RUM session
  `462f633d-b3fb-4fd5-83e6-bd83123187ee`, validates both structured-task action
  boundaries. Request `74b9feb7-ca7e-4669-8bd3-bac9e18b9368` produced resource
  `b04b59e6-cb2f-4795-b8dd-aa8f1cbf296c` on B Home with action
  `d9aa94f4-1a0a-4da2-96fa-35e16c6e04a5` after a yield and 20 ms suspension.
  Request `1dddb2ca-35ea-4ec4-bed7-d1465bccbdb6` produced resource
  `20428a3f-e94f-4414-8c05-e0c1875397eb` on the same view without an action after
  200 ms, as required by the 100 ms discrete-action expiry.
- The same run disproved the previous claim that explicit rollover was covered.
  Stopping the session from B Home and immediately navigating B to Detail created
  session `2df86288-72c8-43dc-ab53-7d13d70c6367` and correctly attached delayed
  request `704dfa3b-3906-48cc-a7b7-005a81d5333a` to B Detail, but did not restore
  any A view into the new session. The timeout-focused regression exercised a
  different renewal path and could not detect this explicit-stop loss.
- A new regression reproduces that exact sequence. It failed with one active view
  instead of two before the fix. Session restart now excludes only the view branch
  being replaced by the scene-targeted start/stop command, restores every other
  foreground scene, and emits a synthetic boundary update only for a restored view
  that did not already emit while processing the trigger. The new regression and
  the existing explicit-action, inactivity-timeout, and max-duration cases pass
  together, 4/4. The complete DatadogRUM suite then passed 1,005/1,005.
- Fixed live run `e03e31d3-eb19-4955-9782-1b583f37b28f` began in session
  `aeafc8d8-8c9f-4bf5-8521-e3c41063219c`. Repeating the compound control created
  explicit-stop session `29784a34-5196-4ed1-8c56-8e3337f31205`, restored A Home
  as view `42d80ad8-775b-44f2-a10f-bdea2ba50227`, and started B Detail 1 as view
  `7eb3a288-5fdf-4162-9160-09facee6bf9f`. Delayed request
  `ccbc1dbc-e6ca-4cab-af90-810efa1fcf32` produced resource
  `7c06fa6c-e61b-4e1f-be1f-e9a047ba798f` on B Detail. Console and backend raw
  intake both contain the two new-session view IDs and the correctly routed
  resource. The session reducer initially reported `view.count:1` while the
  second view update was still being reduced. After activity in restored A and
  B's scene closure, the same session document converged to `view.count:2`, chose
  A Home as its initial view, and retained two resources. This was intake lag,
  not evidence of a backend overlapping-view limitation.
- Focused reruns confirm that a timeout triggered by stopping scene A transfers
  and initializes unaffected scene B, an unscoped continuous-action stop ends
  only the representative action, and interaction in B still expires a stale
  discrete action in A. These three audit cases pass; the cross-window action-stop
  blocker remains covered by the current implementation.
- Delayed-provenance run `70ccd6cf-1514-4387-86ef-25cc255744c4`, RUM session
  `8ea9108c-3fb3-4cdf-ae76-c429348b16b0`, scheduled four requests from B Home
  (`607abb86-12db-40cc-bbbc-79e9844d3aa2`) and then made A Home
  (`a1b79f91-a04e-4118-85cc-b5d06947724d`) representative well before their
  three-minute start. Structured-task request
  `d8d0675e-717a-4649-ba3c-37a8cdc39564` retained B through suspension. Detached
  task `3fa81cb7-752d-4068-ba38-ac374fb009dc`, GCD
  `143f67c5-b01c-443d-b0ac-708e3ceaf3f0`, and timer
  `09412301-8cc8-421a-8ed3-091f3e309a03` all used representative A. Console
  payloads, all four backend RUM Resource documents, and APM aggregation by
  `_dd.view.id` agree. This is the tested automatic-attribution boundary:
  structured inheritance works; provenance lost to detached/GCD/timer scheduling
  cannot be recovered automatically.
- A custom URLSession handler experiment changed an already instrumented request
  across capture and first-party/disallow boundaries. A finalization hook could
  defend that sequence, but it added shared networking and tracing complexity for
  a developer-error case rather than a multi-scene requirement. Product guidance
  explicitly rejected that scope. The hook, header/GraphQL repair, and three tests
  were removed; the normal 43-test resource-handler suite passes. Do not repeat or
  reintroduce this defensive path without a separate networking requirement.
- iOS 27 ordering run `5ebc59df-6fc1-4620-bcb2-1177d9ab3409`, RUM session
  `d49d1cdf-5a6d-4787-af1e-1422ec841ea4`, reproduced a SwiftUI lifecycle defect in
  one scene without exercising the unstable second-window compositor path. Home
  `onAppear` resource `98da1b25-a72b-48d8-a329-b408ede05847` started before Home
  view `31882973-7e07-4793-b097-df4d2c5fb3fb` and landed on preceding UIKit Home
  `91657525-5add-4f00-bc18-122bc7b0fe4c`. Detail resource
  `07c002bd-9483-4e21-9e02-a342949f9f3c` likewise started before Detail view
  `b4e265a6-fc43-4d24-b625-960d2cd9a85e` and landed on SwiftUI Home. Both delayed
  `.task` requests started after their views and were correct; that did not test
  the synchronous prefix because the probe yielded and slept first.
- The next SwiftUI experiment reported the destination window in
  `willMove(toWindow:)`, retained lifecycle identity in reference-backed state,
  and treated detachment separately from an attached legacy window with no
  scene. Seven initial state/observer tests passed, but rebuilt runtime evidence disproved
  the ordering hypothesis. Run `fd44bcd2-cde3-4488-a9f4-7756683d85f4`, RUM
  session `dab21bf2-8fee-406a-bd84-81b7211e934e`, attributed Home `.onAppear`
  resource `aab3afbb-e0dc-4264-bc1a-aa15080866da` and immediate `.task`
  resource `6f559479-5459-4df0-87ab-9b0a68949581` to preceding UIKit Home
  `baecfe4b-20cc-435f-94f2-806629ffe2ea`. Detail `.onAppear` resource
  `833d9ae6-3467-4d0d-9add-2df5733e7807` and immediate `.task` resource
  `408f5be9-8c28-4683-b395-bbfa1f1e2f0d` similarly landed on preceding SwiftUI
  Home `efff3c99-ad99-475c-b39d-4158f8458be0`. Only the delayed `.task`
  resources were correct. Navigation also emitted backend-indexed duplicate Home
  view `00d24725-3925-4990-9e1c-57fc9d3d92ad` for 791,907 ns before Detail.
  This hook is an attachment detector, not an appearance-ordering fix. The state
  machine now ignores transient detach/reattach in the same scene, migrates only
  when a different scene resolves, and stops the original owner on disappearance;
  ten focused lifecycle tests pass and rebuilt runtime verification is pending.
- A follow-up child-controller experiment tried to obtain scene attachment from
  `UIViewControllerRepresentable.viewWillAppear`. Run
  `16e48aa6-6826-49ea-b764-6c0af6f16c0b`, RUM session
  `c8c5b90c-ef71-4bbe-842a-fa22ed5587fd`, disproved that path as well. Home
  `.onAppear` resource `4da8eaa8-56e2-4890-b6ec-6a8eb2ab8b4e` and immediate
  `.task` resource `d2b8ab05-e7ad-4683-b395-bbfa1f1e2f0d` preceded SwiftUI Home
  by 35/34 ms and landed on UIKit Home. Detail equivalents
  `717b1d98-5b5b-45e2-98eb-d76080d7c781` and
  `d1326f13-5890-4a92-a9ee-01f853f8b6fa` preceded Detail by 5/4 ms and landed
  on SwiftUI Home. Delayed tasks remained correct. The run emitted exactly four
  expected views, no duplicate/helper view, zero RUM errors or crashes, and
  accepted Session Replay uploads. The controller and its UIKit exclusion were
  removed because they added overhead without improving ordering.
- The scene-only SwiftUI reader and UI-event causal swizzle are now gated by the
  configured bundle's `UIApplicationSupportsMultipleScenes` value. Ordinary
  apps use the original modifier lifecycle and action-only dispatch path. Ten
  lifecycle tests plus four gating/handoff regressions pass; the complete RUM
  suite passes 1,018/1,018. The `RUM MultiScene Probe` then rebuilt successfully
  through Xcode in 14.997 seconds.

### 2026-09-12 — Checkpoint review cleanup

- An independent diff review found that the extra UI-event causal handoff still
  ran when an ordinary app enabled automatic action tracking. The handler now
  scopes downstream work only when the configured app declares multi-scene
  support; ordinary action tracking retains its original publish-then-dispatch
  behavior. A direct regression test covers this boundary.
- The request-local handoff's four thread-dictionary keys and exact-nil decoding
  had been reconstructed in RUM, Internal, Logs, and Trace. `DatadogInternal` now
  owns that private SPI contract and restores nested values; all consumers read
  one coherent snapshot.
- Feature-operation API commands now consume a known handoff scene, and the
  session scope resolves that scene before recording operation start ownership.
  Tests prove a scene-A operation does not start on representative scene B and
  continues on scene A after navigation.
- The review rejected substituting representative-session baggage when a request
  already contains customer trace headers. Removing all existing-header handling
  initially broke the established no-header-mutation test, so the final behavior
  keeps that compatibility boundary without representative fallback: it adds no
  RUM session baggage to a pre-traced request while retaining the source-scene RUM
  context for the local span.
- Added an iOS 17+/visionOS 1+ scene trait publisher for apps declaring multiple
  scenes. It seeds `UIWindowScene.traitOverrides` with the real persistent scene
  identifier and bridges that private trait into SwiftUI. Ordinary apps do not
  construct the publisher; iOS 15/16 continue through the attachment-backed path.
  Three focused activation/value tests and ten existing lifecycle-state tests pass.
- First trait run `68786559-42b4-4087-8e34-997e77d081c5`, RUM session
  `799d975d-9597-4b2e-9c4e-833835aed5de`, started SwiftUI Home after customer
  `.onAppear`/immediate `.task` by 35/34 ms and Detail by 2/1 ms. Unlike the
  attachment-only and child-controller runs, all six resulting URLSession
  resources were ultimately indexed on their correct Home or Detail view. The
  source Home navigation action also remained correct, and intake reported zero
  errors/crashes with Session Replay present.
- Second trait run `92326a81-441e-48b9-97b3-3db2b00bc3ab`, RUM session
  `4bd7fa85-dda2-4712-9cce-33cb23f73a3c`, used
  `onChange(of:initial:)` as the earliest supported lifecycle callback. Home
  outer `.onAppear` and immediate `.task` still preceded the RUM view by 2.825 ms
  and 2.222 ms; Detail preceded it by 3.468 ms and 2.696 ms. The later modifier
  tasks ran about 100 ms after their views. Datadog intake again contains all six
  resources on the correct views, the navigation action on source Home, four
  expected views, and a session with zero errors/crashes. This narrows but does
  not eliminate the ordering gap.
- Synchronous-action run `c77883d4-80fe-4730-a3ff-575221a3c262`, RUM session
  `67fdbd11-1d6a-440d-afd0-db11ff6bc6c4`, temporarily invoked custom RUM actions
  at the beginning of customer outer `.onAppear` and immediate `.task`. The four
  invocations preceded their Home/Detail view payloads by 0.292-4.128 ms, but the
  serial RUM queue processed the view transitions first. All four actions were
  emitted once on their intended new views; the navigation action stayed on
  source Home, all six lifecycle resources were correct, and Datadog intake
  reports five actions with zero errors/crashes. The probe-only actions were then
  removed to avoid perturbing the broader interaction matrix.
- The complete post-trait `DatadogRUM` suite passed 1,020/1,020 on the iOS 27
  simulator. This supersedes the 13-test focused checkpoint while retaining
  1,018/1,018 as the pre-trait baseline.

### 2026-09-12 — Broad fixed-runtime matrix and scene teardown

- Run `91864fb5-cace-4f29-a348-5769bf2ffa65`, RUM session
  `02b150f8-3b2f-43fd-b032-8cac2ef91cd9`, produced 46 events: 9 views,
  16 actions, 14 resources, 2 long tasks, zero errors/crashes, and replay. A
  SwiftUI scene-B operation and manual resource retained B Detail while scene C
  opened. Scene C connection and initial lifecycle resources landed on the
  previous representative B Detail because they began before C's first RUM view;
  this is the approved source-less fallback boundary, not a header-injection
  defect.
- Run `31d0a951-095a-4a71-8c48-b6e4fb4d0af2`, RUM session
  `3160c14e-95d7-4a0e-a40b-204060cfae45`, proved UIKit modal
  presentation/dismissal and duplicate-name A/B views remain independent. The
  first delayed switch result was invalid because the scrolled control tree was
  stale. Both UIKit and SwiftUI probe screens now expose fixed Close and Other
  Window toolbar controls so switching and teardown do not depend on scroll
  position. SwiftUI uses the non-deprecated `.topBarLeading` and
  `.topBarTrailing` placements.
- Run `76599137-09c8-4fb1-b54a-92b3c9ff04d1`, RUM session
  `725418d9-aae5-4570-8bd0-1bad452bbb8c`, repeated the delayed UIKit flow with
  the fixed controls. The B Home trace and operation kept B ownership while A
  became active. APM trace `6aa50e250000000095c6c6caacd03265` retained resource
  `probe-span-scene-B` and the B source view.
- Broad run `972c83f7-9c13-4ea3-b5b6-d43857bb7815`, RUM session
  `3a8b0c3b-53e4-4426-b4b1-12e92ec715d5`, reached 18 views, 17 actions,
  33 resources, 4 long tasks, zero errors/crashes, and replay. UIKit and SwiftUI
  modal/dismiss flows, duplicate-name views, SwiftUI scroll, delayed resources,
  and origin-scene closure retained their source windows. UIKit trace
  `6aa50f23000000001829c0dfb272bbb9` and SwiftUI trace
  `6aa5128c0000000048ed46829eb03478` retained their destroyed source scenes.
- Closing a nested SwiftUI scene D caused customer `.onAppear` and `.task`
  callbacks to run again after its tracked view stopped; three lifecycle requests
  then used the Background representative. Closing another SwiftUI scene from
  Home did not reproduce it. The callbacks no longer expose a public source-scene
  identity once detached, so tombstoning them in the SDK would risk dropping
  legitimate work. Keep this as a targeted teardown/restoration experiment rather
  than inferring a fix from one nested callback sequence.
- The broad run exposed a distinct operation defect. Raw start vitals for UIKit B
  key `5EC831AF-0135-4AE6-B74A-088B292787BE` and SwiftUI E key
  `EC54293B-2ED0-4D97-8C89-B308FCE020BC` reached intake on their correct source
  views, but no end vital arrived and no reduced operation existed. The manager
  deliberately selected no active view after the owner scene closed; a null-view
  end step was therefore not sufficient to preserve the operation.
- The teardown fix made `RUMFeatureOperationManager` retain a lightweight last-
  proven view ID, name, and path. Its first implementation followed the start
  scene's current view, refreshed after navigation there, and used the snapshot
  after teardown. This proved that a stopped view need not be retained or
  resurrected. The later cross-window contract keeps the snapshot mechanism but
  removes permanent start-scene ownership: every trustworthy step can replace it,
  including a step in another scene. The original 17 manager tests passed; the
  superseding focused Operations set now passes 98/98 across manager and session
  scope.
- Post-fix run `c8d2aa31-127a-4d4c-a910-8e56eea5fb48`, RUM session
  `6c05508c-18fc-41df-85e8-32c573fbf37e`, used one ordered HID batch to start
  operation key `206E691E-33AC-4BF1-8D26-E48D81315D9A` in UIKit scene D and
  close D one second later. Intake contains start at `09:31:59.034Z` and end at
  `09:32:02.184Z`, both on D Home view
  `547eb0b9-5743-47f7-ab07-c309e5b5bb29`. The reducer created one successful
  3.15-second operation whose start and end views are that same D view. The final
  session contains 8 resources, 8 views, 7 actions, 3 vitals, 1 long task,
  1 operation, and 1 session; replay is available.
- The first complete command-line RUM rerun reported one timing-sensitive failure
  in the unrelated timeseries pause test: its pause flush increased the event
  count from two to three. Xcode then spent several minutes collecting simulator
  diagnostics, so that run was interrupted after all 980 XCTest cases had
  otherwise completed. The exact test immediately passed 1/1 through Xcode MCP.
  A fresh complete Xcode MCP run then passed 1,022/1,022 with zero failures,
  skips, or tests not run. The generic iOS `Datadog-Package` Swift Package build
  also succeeded through Xcode 27 and restored the temporarily hidden workspace.
  Repository lint and `git diff --check` are clean.

### 2026-09-12 — Goal-backward review

- At this checkpoint, auditing the probe against the original objective found
  that all SwiftUI runtime view evidence used explicit `.trackRUMView`;
  `swiftUIViewsPredicate` was disabled and SwiftUI was hosted by the runner's
  UIKit scene delegate. That gap was promoted to P0 and has since been exercised
  in both automatic UIKit-hosted and native `WindowGroup` runs. Both now provide
  failing baselines rather than being silently included in the support claim.
- The accepted “last-interacted” fallback currently means the RUM process
  representative. A predicate-filtered touch supplies scene provenance to work
  executed inside dispatch but emits no interaction command that would necessarily
  advance the later representative. No focused post-dispatch manual-API experiment
  has been run; it is now an explicit edge rather than an assumed guarantee.
- The explicit-session-stop experiment already proved raw intake and the backend
  session reducer accept overlapping scene views: the reducer converged to
  `view.count:2`. Only product UI presentation and analytics semantics remain
  unchecked.
- Operation teardown is fixed for unique identities. The later contract decision
  confirms that local and backend identity intentionally omit scene. Focused tests
  now validate duplicate `(name, key)` starts, parallel distinct keys, reverse
  completion, and cross-window view changes; live backend validation remains.
- The remaining downstream runtime plan requires probe work first. The current
  logger control emits `.info` rather than a mirrored RUM error, and there are no
  WebView, split-navigation, restoration, fatal-context, or exported-context
  controls. The shared-request helper is one-shot, and “Other Window” is ambiguous
  once more than two sessions exist.

### 2026-09-12 — Automatic SwiftUI tracking baseline

- The existing probe now selects between its previous explicit `.trackRUMView`
  behavior and `DefaultSwiftUIRUMViewsPredicate` with
  `DD_MULTI_SCENE_SWIFTUI_VIEW_TRACKING`. Manual remains the default, so all prior
  runs and ordinary probe launches keep their previous behavior. The automatic
  variant removes only the explicit view modifier; action tracking and the same
  UIKit scene delegate remain enabled. Xcode 27 rebuilt the probe successfully on
  the iPadOS 26.5 destination.
- Control run `0b5749cf-e4fd-4bd5-a3e8-4789d3ee6d97`, session
  `cc9e9e0c-1f85-401b-9f33-ba66843b9e50`, launched the same binary with manual
  mode. Explicit tracking created `SwiftUI scene-A Home`
  `63b52dac-d854-498e-951b-137d59eef48e` before the three lifecycle requests
  completed. All three resources use that view in the backend, with no transient
  automatic root. The session has 12 events, zero errors/crashes, and replay.
- Automatic run `76f40f1f-554f-4842-86a1-7bf4955b734c`, RUM session
  `ae9530b4-4117-4895-a1fe-7442a160e76f`, reproduced the same ordering in both
  scenes. Scene A's three SwiftUI Home lifecycle requests first completed on UIKit
  Home `7b1be550-1311-4017-8813-65847a2182da`; only afterward did automatic
  tracking emit transient root `2d15f54c-b6ce-4793-9526-0bfe2591e1ef` and active
  navigation host `9c37bebb-d4b7-4519-bf52-42c069dd2962`. Scene B repeated that
  sequence from UIKit Home `95668237-673d-4e11-ac71-d65b61d3c418` through root
  `8b52edfa-4d51-414e-b05d-c46693dc5a1b` to navigation host
  `6a1e9fac-d2e6-4e95-9f1c-2bded75541d2`.
- SwiftUI detail navigation makes the semantic defect more direct. Scene B's
  `.onAppear`, immediate `.task`, and task-modifier resources all completed on its
  source navigation host `6a1e9fac-d2e6-4e95-9f1c-2bded75541d2`. The tap action
  was also correctly attributed there, then the tracker emitted transient root
  `a67ddc8d-d3e2-4b36-99b4-cdff41b65863` and final Detail
  `9887bd8a-e850-44bc-8a1e-d256bb4a7102`. Scene A repeated the same sequence from
  reactivated host `01f5d769-4732-4e17-96d9-21b5ba5f4333` through transient root
  `cec5e006-88c0-4c50-b7f3-66885ababe77` to Detail
  `61cfefe2-5848-4da6-bc10-b4a972e689be`.
- Alternating scenes did not cross their view branches. Reactivating scene B
  created Detail view `56acd446-462b-4188-a6ca-e553b82c2be5` and stopped only A's
  current Detail. Closing B stopped only that B view. Three SwiftUI lifecycle
  callbacks then ran again after detachment and their resources used Background
  view `8941267e-f589-407f-b65f-3148e17390d3`, never scene A. This matches the
  earlier nested-close observation and remains a teardown/restoration edge, not a
  reason to guess another scene.
- Datadog lookup initially failed during a local Wi-Fi interruption and succeeded
  on retry. Exact-session intake confirms the console's view IDs, source-scene
  actions, preceding-view resources, transient roots, and final destinations.
  The session reports zero crashes and Session Replay available. The Stage Manager
  arrangement displayed one probe window at a time and returned to SpringBoard
  after closing B, so this run does not replace the broader simultaneous-window
  evidence and does not establish automatic behavior in a native SwiftUI app.
- Target-runtime run `5c807364-100d-44b1-8d35-9d5cfd802fc5`, session
  `2133b271-2079-4d9c-b570-fcea81e1f062`, repeated Home -> Detail on an iPadOS 27
  simulator without opening a second window. Home `.onAppear` and immediate
  `.task` resources stayed on UIKit Home
  `4f32626f-0467-4567-a19c-d9e7d392d776`; the delayed task-modifier resource used
  final navigation host `d1c35ad8-3bc7-4faa-93fe-c37eb3d3b4cc`. On Detail, all
  three lifecycle resources and action `b469f984-051b-4784-a543-a429668b7164`
  stayed on that source host. Automatic tracking then emitted transient root
  `82f273ff-f75e-46bb-bc4d-4c1e560a4e22` and final Detail
  `f0b78f55-f0ca-46a0-a330-9391df1d6fa9`. Backend intake contains 21 events,
  including six views, eight resources, one action, zero errors/crashes, and
  replay. This establishes target-OS relevance without invoking the known
  second-window compositor failure.
- A narrowly gated follow-up temporarily intercepted
  `UIViewController.viewIsAppearing` only for iOS 27 multi-scene applications
  with automatic SwiftUI view tracking. Three focused tests and then both full
  `RUMInstrumentationTests`/`RUMViewsHandlerTests` classes passed (53/53). The
  integration probe also built successfully and the full linter reported zero
  violations. This established that the candidate composed with the current
  swizzler and preserved UIKit-predicate precedence; it did not establish useful
  runtime ordering.
- Rejected run `13e39eae-ccc8-47a6-8125-3f52fab589b8`, session
  `092c7b63-661e-4f8c-a8ff-b21b92665c96`, measured the actual ordering on iPadOS
  27. Home `.onAppear` ran at `14:52:12.666749` and immediate `.task` at
  `14:52:12.667454`; the transient root did not start until
  `14:52:12.736296`, followed by the navigation host at `14:52:12.740000`.
  Those first two resources remained on UIKit Home; only the delayed task used
  the navigation host.
- On Detail, `.onAppear` ran at `14:52:44.169378`, immediate `.task` at
  `14:52:44.169823`, and the delayed task at `14:52:44.275860`. All three
  resources remained on source navigation host
  `eef201a0-ae06-4a0b-a4da-849aebd8b605`. The source view stopped only at
  `14:52:44.683788`; transient root
  `2d7bfd77-fc7f-41b4-8f5b-2e9a246bad57` followed, and final destination
  `0eda31f6-317d-4905-b1f0-a5bee6495b2d` started at
  `14:52:44.684773`, about 515 ms after destination `.onAppear`. Backend intake
  matches the console IDs and attribution. A later manual action and three-second
  resource correctly used the final view, uploads returned HTTP 202, replay was
  available, and no crash occurred.
- Because the added lifecycle interception neither advanced view discovery nor
  removed the transient root, all candidate production and test changes were
  removed. This is a completed negative experiment, not pending implementation.
- Conclusion: the branch's scene-keyed routing also works for controllers found by
  automatic SwiftUI tracking, but automatic view creation/navigation itself does
  not yet meet the objective. Its destination appears too late for lifecycle work
  and the extra root view makes the backend navigation chain noisy. Treat these as
  a general automatic-tracking semantic defect exposed by the multi-scene matrix,
  separate from cross-scene owner selection.

### 2026-09-12 — Cross-window RUM Operations contract

- The operation identity decision is now explicit: exact `(name, operationKey)`
  is application-wide and scenes never namespace it. Parallel same-name instances
  require unique opaque keys and every step for one instance must reuse the same
  tuple.
- The prior permanent start-scene rule was removed. Every start, update, retry,
  success, and failure now resolves a trustworthy call-site target independently.
  A resolved target refreshes the operation's retained last-proven view snapshot;
  an unresolved or source-less later step uses that snapshot before falling back
  to the process representative. The snapshot remains lightweight and cannot
  reactivate or update a stopped view scope.
- Starting the same identity twice emits both requested start vitals, logs that
  only the latest is tracked locally, and does not synthesize an end. One later
  success or failure ends the latest instance. The warning explains that the
  earlier backend operation remains open until its four-hour timeout and
  recommends a unique `operationKey`.
- The Operations-focused Xcode run passed 98/98: 26 manager tests and 72 session-
  scope tests. Coverage includes A start/B success, A start/B failure, A1 -> A2,
  parallel same-name/different-key instances, reverse completion, a trustworthy B
  step overriding the stored A snapshot, explicit scene targeting overriding an
  incorrect process representative, closed-scene snapshot fallback, explicit B
  completion after A closes, duplicate starts with no synthetic end, typed-
  identity collision resistance, legacy/source-less compatibility, and the
  process-representative fallback when a target cannot resolve and no snapshot
  exists.
- The complete post-change `DatadogRUM` Xcode run passed 1,033/1,033 with zero
  failures, skips, expected failures, or tests not run. Its result bundle is
  `Test-DatadogRUM-2026.09.12_15-56-14-+0200.xcresult`.
- A downstream identity audit found that both Profiling implementations still
  indexed operation messages with `"\(name)-\(operationKey)"`. Commit
  `ac90b5865` replaces those string keys with an exact typed tuple and tests both
  a delimiter collision and omitted-versus-empty keys. The first build exposed
  one stale `[String: Vital]` helper annotation; after correcting it, the
  complete `DatadogProfiling` scheme passed 233/233 and repository lint passed
  with zero violations. Do not restore delimiter-based correlation.
- Public API was not added speculatively. The proposal above supports inferred
  behavior, current view in a `UIWindowScene`, manual view key plus scene, and a
  tracked `UIViewController` without exposing RUM UUIDs. The review established
  that explicit and inferred candidates must remain separate, that additive
  extension-only overloads avoid changing protocol witness requirements, and
  that the `view` argument must remain required to avoid overload ambiguity.
  The later product direction fixed the duplicate-start behavior and the
  four-hour orphaned-operation warning. API review is still required for the scene-targeted
  manual-key prerequisite and final public type/selectors.
- The probe now has fixed UIKit and SwiftUI controls to start/duplicate-start,
  succeed, or
  fail one app-scoped cross-window key. It built and launched on the stable iPadOS
  26.5 simulator as probe run `c28442df-d11a-456b-9ca7-1ffe13bad483`, RUM session
  `722d9a8b-5a00-4ab7-8d02-e609baaf7bb3`. The Mac GUI was locked: the accessibility
  tree exposed the controls, but injected taps did not invoke them. This launch is
  setup evidence only, not an A-to-B runtime pass. Resume the same three flows
  after unlock rather than interpreting the inactive controls or retrying HID.
- After the reported Wi-Fi failure cleared, a fresh Datadog query for run
  `c8d2aa31-127a-4d4c-a910-8e56eea5fb48` again returned both raw operation-step
  vitals and the reduced success in session
  `6c05508c-18fc-41df-85e8-32c573fbf37e`. The reduced duration is 3.15 seconds;
  start and end both reference scene D view
  `547eb0b9-5743-47f7-ab07-c309e5b5bb29`. This revalidates connector access and
  the teardown proof only; it is not the pending A-to-B experiment.

### 2026-09-12 — Rejected base-`viewWillAppear` SwiftUI experiment

- Apple's lifecycle contract places `viewWillAppear` before UIKit adds the view
  to the hierarchy, so an owning `windowScene` is not generally available there.
  An iPadOS 27 LLDB run nevertheless found the exact
  `RUMSceneIdentifierTrait` on both the outer `UIHostingController` and inner
  `NavigationStackHostingController` at the base implementation entry. The outer
  controller's parent was already attached to the scene window; the inner
  controller and its parent were not. This establishes the trait as the reliable
  early scene input, with attached ancestry as a useful secondary source.
- A candidate optionally intercepted base `UIViewController.viewWillAppear` only
  for iOS 17+/visionOS 1+ declared multi-scene apps with automatic SwiftUI view
  tracking. It used the trait, attached ancestry, or a presenting controller to
  resolve scene ownership, preserved UIKit predicate precedence, and fell back to
  the established `viewDidAppear` path when early discovery was unavailable.
  Focused tests covered early start/deduplication, unresolved-scene fallback,
  predicate precedence, and swizzler ordering.
- Probe run `b4bbfa9a-3094-4345-b64e-bb1728bec061` used automatic tracking and
  launch-controlled Home -> Detail navigation on the iPadOS 27 simulator. The
  Home `.onAppear` and immediate `.task` resources still resolved to
  `ApplicationLaunch` view `802783a4-2384-4da5-b9b3-162738a85487`; the delayed
  Home task used navigation host `7f2ca0fc-31fe-4902-bafb-7a7029b2758c`. On
  Detail, `.onAppear`, immediate `.task`, and delayed `.task` also used
  `7f2ca0fc-31fe-4902-bafb-7a7029b2758c`. The repeated class name initially looked
  promising, but the exact ID proves it was still the Home/source view, not a new
  destination view.
- Datadog intake for session `ae51b4e7-c88b-4413-98bb-455f93c38dd6` agrees:
  17 events, 5 views, 7 resources, zero errors/crashes, and Session Replay
  available. It retains short-lived outer-root views
  `7e66ee40-e4d4-4dd5-ad84-a1ba270cd0f5` and
  `87f53c3f-ba5a-4158-b9cf-373933f2915e`, so view identity/noise remains an open
  part of the P0.
- A follow-up moved notification from immediately before to immediately after the
  base implementation while remaining inside the subclass's `super` call. Run
  `20462f01-45d6-4838-9102-151467c4c47f`, session
  `da12ef5f-539e-4821-afa9-c2814e63be91`, produced the same exact-ID result:
  Home lifecycle work used `ApplicationLaunch`, and the delayed Home task plus
  all three Detail resources used Home host
  `445ec932-6eb3-49bf-a25b-aff6bacbc29a`. Intake contains 16 events, 5 views,
  7 resources, zero errors/crashes, and replay.
- Before removal, four focused handler/instrumentation tests and all three
  swizzler tests passed. The candidate build completed, the temporary full RUM
  run passed 1,037/1,037 including the four candidate tests, and the repository
  linter reported zero violations. These prove composition, not semantic value.
  The full `DatadogCore` scheme was not a clean baseline on this iOS 27 simulator:
  813 passed, 3 skipped, and 3 unrelated tests failed.
  `BrightnessLevelPublisherTests/testMultipleBrightnessChanges()` crashed,
  `CrashReportReceiverTests/testReceiveCrashAndViewEvent()` rejected its fixture,
  and `TracingURLSessionHandlerTests/testGivenAllTracingHeaderTypes_itUsesTheSameIds()`
  observed a baggage session-ID mismatch. Each failure reproduced when run alone.
- Exact backend IDs showed no destination improvement, so the production hook,
  protocol method, mocks, and candidate tests were removed. A real NavigationLink
  tap was attempted as a final differentiator in run
  `fb857d2d-450a-4e80-993c-c57e6b72be19`, session
  `1e97266b-253a-4141-9cf0-37399e071040`, but Xcode device interaction held a
  stale session and CUA confirmed that the Mac was locked. No tap occurred; the
  launch-controlled state transition is the completed evidence for this
  candidate, while a physical post-fix tap remains part of any future distinct
  implementation's validation.
- After removal, the integration probe rebuilt successfully and the complete
  `DatadogRUM` scheme returned to its current 1,033/1,033 pass. The final scoped
  diff has no production lifecycle hook or candidate test residue.
- The probe retains the opt-in
  `DD_MULTI_SCENE_AUTORUN_SWIFTUI_DETAIL=1` capability and starts on its SwiftUI
  tab in automatic mode. The temporary automatic/autorun values were removed
  from the shared scheme after the run.
- This checkpoint's next step was a native `WindowGroup`/`openWindow` exact-ID
  comparison. That work is complete in the two following experiments and no
  longer remains a pending plan item.

### 2026-09-12 — Native SwiftUI `WindowGroup` baseline

- Added an isolated iOS 27 app in `Datadog/Example/MultiSceneProbe` instead of
  changing the already-dirty main `Datadog.xcodeproj`. XcodeGen links the local
  `DatadogCore` and `DatadogRUM` package products and reads the existing token and
  application-ID build settings through `xcconfigs/Datadog.xcconfig`; no secret
  value is copied into the probe. The native `@main App` declares a typed
  `WindowGroup`, bound `NavigationStack`, and deterministic `openWindow` flow.
- The first generated build inherited the SDK's iOS 15 deployment target from the
  shared xcconfig despite XcodeGen's target declaration. Adding an explicit target
  `IPHONEOS_DEPLOYMENT_TARGET = 27.0` fixed availability checking. The next build
  showed that Xcode 27 supplies a non-optional typed-window binding when
  `defaultValue` is present; removing the stale optional unwrap fixed it. The
  third Xcode MCP build succeeded against the iPadOS 27 SDK. Preserve both project
  settings when regenerating instead of repeating those compiler failures.
- Every Home and Detail lifecycle phase emits one synchronous custom action and
  one 50 ms manual resource with run, logical scene, native scene, screen, phase,
  and monotonic-time attributes. Event mappers print the exact RUM session and
  view IDs. The probe's own hidden `UIViewRepresentable` still reported
  `unresolved` during Home `.onAppear` and immediate `.task`, then resolved the
  real scene session before navigation. This independently demonstrates why an
  attachment reader cannot be the early automatic source.
- Two-window run `native-swiftui-20260912171529` opened scene B without a tap.
  Scene A native session `69412B88-C4BC-4A9C-A7CB-484C166BACA6` and scene B
  native session `1F1874F2-6843-4AE8-AAA9-83E138C8E3A2` were distinct. B Home
  `.onAppear` and immediate `.task` nevertheless emitted on A's final Detail RUM
  view `b33cbe9a-4613-4327-9e2f-a6ceadba5896`; B's navigation host appeared only
  afterward. The final B `ProbeDetailView` also appeared after all three Detail
  phases. This is a real cross-window semantic failure, not only a naming issue.
- After uninstalling the probe to clear restored window state, single-window run
  `native-single-20260912171659` reproduced the generic ordering without scene B.
  Home `.onAppear` and immediate `.task` used `ApplicationLaunch`; delayed Home
  and all Detail phases used the preceding navigation host. No automatic
  `ProbeHomeView` was emitted, and final `ProbeDetailView` started after its three
  lifecycle phases. The automatic tracker therefore observes controller identity
  after the semantic SwiftUI transition, even in a native lifecycle.
- Backend query `@context.probe.run_id:<run-id>` matched console attribution
  exactly. The single-window session retained 6 actions and 6 resources in the
  six expected wrong-view buckets. The two-window session retained 12 actions and
  12 resources; both B Home early phases use A Detail, while B delayed Home and
  Detail use B's navigation host. View aggregation found 5 documents for the
  single-window run and 9 for the two-window run, including 2 and 4 transient
  `AutoTracked_HostingController_Fallback` views respectively. View documents
  report zero errors and crashes. Session Replay was intentionally not linked;
  its crash-free requirement already has separate two-window proof.
- This completes the native-lifecycle experiment requested by the plan and rules
  out the Runner's UIKit scene delegate as the cause. Do not add another
  `UIViewController` appearance hook. Continue from supported SwiftUI view/name
  publication on iOS 27 or an explicit root/navigation integration subject to
  normal public API review.

### 2026-09-12 — Native SwiftUI lifecycle and reflection inspection

Experiment `lldb-native-lifecycle-20260912` is local runtime/LLDB evidence only.
It did not change SDK code, emit a distinct backend dataset, or validate payload
attribution. It completed both Home and Detail portions of the inspection against
the standalone iOS 27 `WindowGroup` probe.

- At the generic root `UIHostingController` base `viewWillAppear` entry, its
  navigation title was nil and `childViewControllers` was empty. The application
  already had a connected foreground `UIWindowScene` and window, but the probe's
  child `UIViewRepresentable` still exposed `unresolved` scene identity.
- `ProbeHomeView.onAppear` ran next. At that exact breakpoint the root still had
  no child controller, and the current reflection extractor returned
  `AutoTracked_HostingController_Fallback` for the generic root type.
- `UIKitNavigationController.viewWillAppear` ran only after Home `.onAppear`.
  `NavigationStackHostingController<AnyView>.viewWillAppear` followed with the
  correct `scene-A: Home` navigation title. A breakpoint at the public
  `UIHostingController.viewWillAppear` implementation entry also occurred after
  Home `.onAppear`, so intercepting that override would not repair the ordering.
- On the real Home-to-Detail tap, `ProbeDetailView.onAppear` fired before either
  `UIHostingController.viewWillAppear` or the base UIKit implementation. At the
  callback, the navigation controller already held two hosting controllers and
  its top controller had the correct `scene-A: Detail` title. The SDK had no
  earlier public controller lifecycle callback through which to observe it.
- After Detail `.onAppear` emitted its marker, the direct
  `UIHostingController.viewWillAppear` entry fired for the destination and still
  carried the correct Detail title; the base UIKit callback followed later. This
  completes the previously pending Detail-navigation portion.
- The iOS 27 reflected `NavigationStackHostingController<AnyView>` structure no
  longer has the existing `content.list.item.type` path. Its `content.list`
  contains `elements`, `implicitID`, `traitKeys`, and `traits`.
  `elements.body.viewType` resolves to
  `NavigationDestinationModifier<ProbeRoute, ProbeDetailView>.Type` while Home
  is visible. It exposes the registered destination type, not the active screen,
  and would falsely create Detail at launch.

Conclusion: the failure is an observation and semantic-identity boundary, not a
missing scene token or a one-segment reflection update. Do not use navigation
titles as customer view names, replace the old path with `elements.body.viewType`,
or add another controller appearance swizzle. The next distinct path is a reviewed
explicit SwiftUI root/navigation integration that knows application semantics
before customer lifecycle work.

### Attempts not to repeat

- Do not infer support from the integration runner merely having a scene delegate;
  its multiple-scenes flag is false.
- Do not retry the unmodified Example target on iOS 27. It builds but cannot launch
  until its app-delegate-owned window is migrated to the required scene lifecycle.
- Do not retry `make ui-test-podinstall` until the locked bundle has been installed
  with a consistent Ruby toolchain; the failure occurs before pod installation.
- After regenerating Pods with CocoaPods 1.15.2 under Xcode 27, reapply the local
  iOS 15 deployment-target workaround before building the Runner.
- Do not use named SDK instances per scene as a shortcut. It would split application
  telemetry and does not solve shared instrumentation or downstream context.
- Do not expose or copy values from `Datadog.local.xcconfig` into source, logs, or
  this document.
- Do not consider callback counts, compilation, or crash safety proof of correct
  semantic attribution.
- Do not query this probe with `@probe.run_id`; use
  `@context.probe.run_id` or fall back to `service:ios-sdk-multi-scene-probe`
  followed by an exact session-ID query.
- Do not classify the first two-window attempt as an SDK crash: the termination
  reason was a simulator `backboardd` respawn and SpringBoard also restarted.
- Do not keep retrying the same iOS 27 half-and-half window arrangement through
  either Xcode device interaction or Device Hub/CUA. All three attempts caused
  the same system-wide `backboardd` respawn before a full alternating flow.
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
- Do not classify the automatic-run return to SpringBoard after requesting scene-B
  destruction as an SDK crash or proof that scene A was destroyed. The backend
  session reports zero crashes, and this Stage Manager arrangement did not
  automatically foreground the hidden window. Use an explicit restoration or
  activation experiment before drawing a lifecycle conclusion.
- Do not invent a provisional scene ID or rebind an existing RUM view piecemeal.
  Ownership is immutable across the view scope, INV tracker, cache, operations,
  lifecycle maps, and snapshots; ordinary stop/start also allocates a new view ID.
- Do not restore permanent start-scene ownership for Operations. It fixed
  same-scene navigation but makes a legitimate A-to-B operation report the wrong
  end view. Retain only a last-proven snapshot and let every trustworthy later
  step replace it.
- After activating the other Device Hub window, refresh the accessibility tree
  before addressing an element by index. A cached B button can still invoke B's
  controller while the screenshot visibly shows A, leaving the representative
  unchanged and invalidating a delayed-provenance experiment.
- The fixed “Other Window” control is predictable only when exactly two sessions
  exist: it selects the first other member of unordered `openSessions`. With more
  windows, verify the recorded target or add explicit target selection first.
- The shared/coalesced request helper stores one task and does not clear it after
  completion. Relaunch or reset/fix that state before a second shared-request run,
  or it can silently join an already completed task.
- Do not look for split navigation, restoration, WebView, fatal/exported-context,
  or mirrored `logger.error` controls in the current probe. They do not exist yet;
  extend the harness before scheduling those rows.
- Do not use separate simulator-driver processes to race a three-second operation
  against scene closure. Process initialization can reverse the taps. Use AXe's
  ordered `batch` command and fixed toolbar controls; the final teardown run
  proves the intended start-then-close order in console and backend data.
- Do not attribute a missing reduced operation to reducer lag without inspecting
  raw `@type:vital` operation steps. The pre-fix teardown runs had a source-scene
  start and no retained end; the post-fix run has both steps and a reduced event.
- Do not treat a successful AXe tap report as simulator interaction while the Mac
  is locked. In run `c28442df-d11a-456b-9ca7-1ffe13bad483`, the accessibility tree
  was readable but the operation controls never invoked and their status remained
  unchanged. Unlock the GUI before resuming the cross-window Operation matrix.

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
