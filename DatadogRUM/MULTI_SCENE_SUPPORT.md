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
an experimental core-RUM implementation that fixes confirmed view, navigation,
action, and lifecycle failures. A real two-window iPad run and the ingested backend
session validate the core view model, but the branch is not ready for a general
multi-scene support claim.** The most recent complete RUM suite passed 1,018/1,018,
including the SwiftUI attachment and normal-app gating changes. Logs passed 95/95,
Internal 477/477, Trace 147/147, and
WebView 31/31. Alternating interaction between both visible windows, scrolls, and
per-scene background/foreground/disconnect transitions still need one complete
fixed-runtime pass.

The baseline verdict is supported by source inspection and a reproduced iPad
simulator failure: opening scene B emitted a final inactive update for scene A's
still-visible Home view before starting scene B's Home view. In the fixed iPadOS
26.5 probe, opening scene B created a second active RUM view without stopping A;
navigating B then stopped and replaced only B. Datadog intake preserved both scene
view IDs in one session. The branch keeps one active view branch per scene and has
focused coverage for UIKit and SwiftUI view lifetimes, duplicate identities,
navigation, taps, scrolls, scene lifecycle, session rollover, and
interaction-to-next-view attribution. Mirrored log errors, unique-key feature
operations, WebView native-container correlation, and the representative fatal
context have focused ownership tests.

Generic automatic Resource and Trace attribution is **not solved**. An arbitrary
`URLSession` request has no intrinsic `UIWindowScene` identity. The current
`UIApplication.sendEvent` experiment can carry provenance only for synchronous
customer code dispatched by a scene-owned UI event, plus structured child tasks
that actually inherit its `TaskLocal` value. It does not establish ownership for
detached tasks, GCD, timers, repositories, background work, framework-created work,
or other requests that have lost their causal origin. Focused tests and one
button-local resource/span probe show that ownership can be preserved when a
source is known; they do not justify a general automatic-attribution claim.

Important limits remain explicit. Source-less manual APIs and feature-flag
messages use the most recently interacted representative view. UI-triggered manual
APIs can participate in the bounded event handoff only when the relevant
instrumentation is enabled and the runtime experiment proves inheritance; callers
outside that path remain inherently ambiguous.
Main-run-loop long tasks, hangs, and other process-wide signals also use one
representative rather than being duplicated. Session Replay scene-correctness is
out of scope for this work; the required contract here is crash-free coexistence,
not correct recording of every concurrent window. Profiling correlation and
external-display refresh-rate collection remain partial.

## Resume here

This branch is a working experimental implementation, not a release-ready support
claim. A new session should continue from this order of work:

1. Preserve the current 1,018/1,018 `DatadogRUM` result as the regression
   baseline, then rerun any module affected by later edits.
2. Rebuild the probe and verify the transient SwiftUI detach correction at
   runtime. Add ordered attachment/appearance transition logging before changing
   that state machine again.
3. Spike the iOS 17+ custom UIKit-trait bridge described in the implementation
   plan. It must prove on iOS 27/27.1 that a real scene identifier exists before
   the customer's outer `.onAppear` and the synchronous prefix of `.task`;
   source inspection or a modifier-local callback is not sufficient. Do not add
   an explicit iOS 15/16 integration solely to extend the support range.
4. Use the iPadOS 26.5 simulator for the complete two-window matrix: alternating
   A/B taps, scroll/deceleration, modal and split navigation, per-scene
   background/foreground/disconnect, reverse completions, and origin-scene close
   before completion.
5. Re-evaluate each provisional Resource/Trace mechanism against the completed
   matrix and remove anything that lacks a reproduced failure and compatibility
   justification. Do not expand this work to defensive request rewriting.
6. Finish normal-app regression, swizzle overhead/recursion, lint, and supported
   platform builds before changing the verdict.

Current implementation state:

- Scene identifiers and routing targets are internal and never serialized.
- UIKit and SwiftUI view stacks, session branches, navigation, actions, scrolls,
  INV, lifecycle, session rollover, exact delayed completions, WebView containers,
  feature operations, and representative fatal context are scene-aware.
- The hidden SwiftUI scene reader and the extra `UIApplication.sendEvent`
  causal handoff are enabled only when the configured application bundle declares
  `UIApplicationSupportsMultipleScenes = true`. Ordinary apps retain the original
  direct SwiftUI modifier lifecycle and swizzling conditions.
- Source-less work still uses the process representative as compatibility
  behavior. This preserves event volume but is not exact multi-scene attribution.
- Session Replay is required only to coexist without an SDK crash. Its recording
  semantics remain explicitly out of scope.

Rejected approaches that must not be restored without new evidence:

- Final-request header rollback, GraphQL reconstruction, or a generic URLSession
  handler finalizer for customer handlers that rewrite eligibility boundaries.
- A child `UIViewControllerRepresentable` per tracked SwiftUI view. The live probe
  proved it did not precede customer lifecycle work, and it adds material UIKit
  lifecycle and allocation complexity.
- Fake scene identifiers or provisional view rebinding. Scene ownership is
  assumed immutable across view scopes, INV, cache, operations, lifecycle, and
  snapshots; a partial rebind can recreate cross-scene replacement or duplicates.
- Further iOS 27 half-and-half second-window attempts until the simulator
  compositor failure changes. The repeated `backboardd` respawn is environmental.

Workspace safety for handoff: do not stage or commit
`Datadog/Datadog.xcodeproj/project.pbxproj` or
`xcconfigs/Datadog.local.xcconfig`; they predate this work, and the latter contains
local credentials. The integration-test project change is part of the probe.

Checkpoint validation on 2026-09-12, after the final review cleanup:

- `DatadogRUM`: 1,018/1,018 tests passed.
- `DatadogInternal`: 477/477 tests passed.
- `DatadogLogs`: 95/95 tests passed.
- `DatadogTrace`: 147/147 tests passed.
- `DatadogWebViewTracking`: 31/31 tests passed.
- `RUM MultiScene Probe`: built successfully through Xcode 27 in 14.997 seconds
  with zero build errors.
- Repository lint and `git diff --check`: clean.

## Checkpoint commit structure

The checkpoint is intentionally split by rollback boundary, in this order:

| Order | Commit subject | Boundary |
| --- | --- | --- |
| 1 | `Route RUM state through concurrent scenes` | Core scene/view/action/lifecycle/session/cache/operation model, plus the private execution-local handoff and focused tests |
| 2 | `Preserve scene ownership for RUM resources` | Network interception and URLSession RUM resource start/completion ownership |
| 3 | `Preserve scene ownership for logs and mirrored errors` | Log correlation and delayed log-to-RUM error routing |
| 4 | `Preserve scene ownership for trace correlation` | Manual spans, URLSession spans, propagation correlation, and completion ownership |
| 5 | `Preserve native scene ownership for WebView RUM` | Native container snapshots forwarded with WebView events |
| 6 | `Add a multi-scene RUM integration probe` | Runner scenario, multi-window scene delegate support, scheme, and project wiring |
| 7 | `Document the multi-scene support checkpoint` | This assessment, experiment ledger, rejected paths, plan review, questions, and resume instructions |

Because `xcconfigs/Datadog.local.xcconfig` already has a user-owned staged entry,
each checkpoint commit must use an exact path list. Do not use a broad `git commit`
or alter that file's staged/working-tree state.

## Consolidated experiment ledger

The chronological notes below retain full IDs and observations. This table is the
authoritative index of runs that currently support decisions:

| Probe run | RUM session | Runtime | What it established |
| --- | --- | --- | --- |
| `a9fab1c4-5cb6-4468-9d1a-dc0936116c46` | `18e48c14-7073-4353-9b85-0121b93c74e0`, then `5fc61f1f-9253-4c12-9917-d1568e4ca9d5` | iPadOS 27 | Single-window harness, payload markers, and backend queries work. The second process showed baseline scene B replacing still-visible A before the compositor restarted. |
| `574be7dd-4482-48e5-b4cc-eaaa332179bd` | `59a3329e-1a21-486c-9ee5-190d111bfbf3` | iPadOS 26.5 | First fixed two-window proof: A and B views coexist; B navigation does not stop A; delayed resource/span/operation retain the intended B lifecycle. |
| `4d7dc23b-721d-4038-8c89-3b29a1c373c9` | `0caa932a-7c4c-4c9d-9fb5-4acb691118f9` | iPadOS 26.5 | Manual B action emits once instead of fanning into A; mixed UIKit/SwiftUI navigation remains scene-isolated. |
| `6a0b61d0-85a8-4915-b02e-63ab53fa13db` | `2b282934-aae9-4495-b7fc-797736f58735` | iPadOS 26.5 | Concurrent UIKit and SwiftUI views coexist; Session Replay uploads are accepted with no SDK crash. |
| `e7bf0f3e-2e46-4487-af4f-072cd7ba8ab8` | `feb94679-4b2e-4821-8146-a531e8608672` | iPadOS 27 | Physical SwiftUI navigation action and destination are correct in one scene; opening B reproduces the simulator compositor crash, not an SDK crash. |
| `da902d8a-f16e-4fa9-b82c-8dcdbaa6dc5f` | `5e65abff-6999-45b2-b8ca-cf199b1b13e4` | iPadOS 26.5 | Actual URLSession boundary: synchronous UIKit work and task resume can retain B; scene connection and `viewDidAppear` loading can fall to representative A. |
| `e03e31d3-eb19-4955-9782-1b583f37b28f` | `29784a34-5196-4ed1-8c56-8e3337f31205` | iPadOS 26.5 | Explicit session stop restores both active scene branches; delayed B work remains on B after navigation. |
| `70ccd6cf-1514-4387-86ef-25cc255744c4` | `8ea9108c-3fb3-4cdf-ae76-c429348b16b0` | iPadOS 26.5 | Three-minute causality proof: structured `Task` retains B; detached task, GCD, and timer use representative A. RUM and APM agree. |
| `5ebc59df-6fc1-4620-bcb2-1177d9ab3409` | `d49d1cdf-5a6d-4787-af1e-1422ec841ea4` | iPadOS 27 | SwiftUI `.onAppear` requests precede the tracked view and land on the preceding view; delayed task work is correct. |
| `fd44bcd2-cde3-4488-a9f4-7756683d85f4` | `dab21bf2-8fee-406a-bd84-81b7211e934e` | iPadOS 27 | `UIView.willMove(toWindow:)` remains too late for `.onAppear` and immediate `.task`; pre-correction navigation emitted a 0.79 ms duplicate Home. |
| `16e48aa6-6826-49ea-b764-6c0af6f16c0b` | `c8c5b90c-ef71-4bbe-842a-fa22ed5587fd` | iPadOS 27 | Child-controller bridge also remains too late. It avoided synthetic/duplicate views in this run and stayed crash-free, but offered no ordering benefit and was removed. |

## Plan alignment review

The plan still matches the original goal after three corrections:

- View creation, independent navigation, action attribution, and scene lifecycle
  remain the primary workstream and have the strongest runtime/backend evidence.
- Resource and Trace work is bounded to preserving trustworthy start-time
  provenance and consistent RUM/APM correlation. Generic source discovery and
  defensive customer-request mutation are not goals.
- Session Replay is evaluated only for crash-free coexistence.

The remaining mismatch is SwiftUI lifecycle ordering. The transparent attachment
reader solves scene ownership only after UIKit attaches it; it does not guarantee
that the RUM view exists before customer outer lifecycle callbacks. The next trait
experiment is therefore directly aligned with proper view creation rather than an
expansion of networking work. Its APIs require iOS 17 and must be availability
gated because the SDK deployment target is iOS 15. The supported multi-scene
contract should guarantee correct attribution before outer `.onAppear` and the
synchronous prefix of `.task` wherever this mechanism can provide it without a
compatibility or lifecycle compromise. No semantic multi-scene guarantee is
required on iOS 15/16, and pre-iOS-27 support does not gate the iPhone Duo goal.

The relevant Apple references are
[Providing data to the view hierarchy with custom traits](https://developer.apple.com/documentation/uikit/providing-data-to-the-view-hierarchy-with-custom-traits)
and [`UIScene.willConnectNotification`](https://developer.apple.com/documentation/uikit/uiscene/willconnectnotification).
Neither reference promises ordering relative to SwiftUI `.onAppear`, so the probe
remains the acceptance criterion.

## Product decisions from the checkpoint review

1. Source-less work keeps the last-interacted representative view. This preserves
   existing instrumentation volume and behavior even though the attribution can
   be ambiguous in a concurrent-scene application. It must be documented as a
   fallback, not described as exact scene ownership.
2. Semantic multi-scene support before iOS 27 is not required for this project.
   The priority is iPhone Duo on iOS 27.1. An explicit scene/root integration for
   iOS 15/16 is therefore not part of the plan.
3. If the iOS 17+ trait mechanism can establish the RUM view before customer outer
   `.onAppear` and the synchronous prefix of `.task` without compromising normal
   apps, the supported contract should guarantee that ordering. Prefer narrowing
   the multi-scene support range over weakening the guarantee for iOS 15/16.

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
- SwiftUI synchronous `onAppear` loading, which two iOS 27 runs attributed to the
  preceding view, including after moving scene resolution to
  `willMove(toWindow:)`;
- the synchronous prefix of SwiftUI `.task`, which the rebuilt iOS 27 probe also
  attributed to the preceding view; only work after suspension currently sees
  the intended RUM view;
- scene connection or `viewDidAppear` work without a scoped callback;
- a request shared or coalesced by multiple scenes.

Thread-local storage is only a synchronous bridge around event dispatch. Thread
identity must never be interpreted as asynchronous scene ownership. The SDK must
not infer an owner from `keyWindow`, the foreground scene, the last active scene,
or the process-representative `RUMCoreContext`, and it must not duplicate one
operation into every active scene.

When provenance does exist, the intended internal contract is:

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
| UIKit navigation | Navigation histories from all scenes interleave | Baseline global stack; branch isolates navigation per scene | B Home -> Detail -> Shared replaced only B | B view chain preserved; A retained independently | Fixed in branch; tests and runtime pass |
| SwiftUI view lifetime | Modifier identities can collide, detach can retain stale scene state, and synchronous lifecycle work can precede the RUM start | Branch resolves the hosting scene only for apps declaring multi-scene support, keeps a stable lifecycle identity, and distinguishes detach from legacy nil-scene attachment; both `willMove(toWindow:)` and a child-controller bridge were tested and are still too late | The rebuilt iOS 27 probe attributes both `.onAppear` and pre-suspension `.task` requests to the preceding view; it also exposed a duplicate 0.79 ms Home view during navigation before transient-detach handling was corrected | Backend view/resource IDs confirm both misattribution and the pre-correction duplicate view | Ten lifecycle-state tests and three normal-app gating/swizzle tests pass; lifecycle ordering remains open and the duplicate-view correction needs rebuilt runtime proof |
| SwiftUI navigation | Hosting controllers from all windows share one active history | Automatic hosting controllers and manual modifiers now resolve scene | `NavigationStack` B Home -> Detail passed; alternating A/B and split-view pending | B Home closed and B Detail opened without cross-scene IDs | Core path fixed; `NavigationSplitView` runtime coverage pending |
| Tap actions | Touch window is available but not propagated to RUM scope routing | Branch retains the touch/modifier scene; new actions no longer fan out to older scene action scopes | UIKit B automatic actions pass; an iPadOS 27 physical SwiftUI tap and `NavigationLink` pass in scene A; alternating physical A/B taps remain pending | UIKit actions correct; manual B action changed from two cross-scene events before fix to exactly one B event after fix; SwiftUI A action used its originating Home | Core path fixed; full two-window physical action matrix pending |
| Scroll actions | Scroll callbacks have a view/window but no scene reaches the command | Branch retains source scene through drag and deceleration | Pending fixed-runtime rerun | Pending | Fixed in branch; focused tests pass |
| Resources and traces | A generic request/span has no intrinsic scene; representative fallback can be wrong | Branch has an experimental `sendEvent`/TaskLocal causal bridge, synchronous owner capture, and frozen completion routing; GCD, detached, timer, repository, lifecycle, and shared work remain ambiguous | With B as source and A made representative before start, structured `Task` stayed on B while detached/GCD/timer work moved to A; scene-B connection and `viewDidAppear` work also use representative A | Intake reproduces the exact boundary: inherited structured work uses B, while the three source-less schedulers and lifecycle work use A | Partial and bounded; generic automatic attribution is confirmed wrong when provenance is absent |
| Manual errors and process-wide long tasks | Source-less APIs/signals have no unique scene | Branch uses one last-interacted representative; no broadcast | Pending | Pending | Explicit fallback policy; not source-attributed |
| Logs and mirrored errors | A log and its later RUM error can resolve different global views | Logger snapshots singular context; error message originally dropped captured view | Pending fixed-runtime rerun | Pending fixed-runtime rerun | Captured-view mirroring fixed and unit-validated; source-scene inference still uses representative context |
| Vitals, TNS, and INV | Process vitals overlap; navigation edges could cross scenes | Branch has one INV tracker per scene; TNS follows resource owner; vitals remain process-derived per view | Pending | Pending | INV/TNS fixed; vitals policy and external displays remain partial |
| Feature operations and flags | Delayed steps receive the global active view; equal keys can collide | Targetless commands and process-global keys | B operation started on Detail 1, navigated, and ended on Shared Detail | Operation start/end views are B Detail 1/B Shared Detail | Unique-key operation lifecycle passes; collisions and flags remain open |
| Session rollover | A process-wide stop/expiry can lose still-visible views or revive the view being replaced | Branch snapshots every active foreground scene and now restores only branches unaffected by a scene-targeted start/stop | Explicit stop followed by B Home -> Detail initially dropped A; fixed rerun emits new A Home and B Detail views | New explicit-stop session contains both raw view documents and the delayed B request remains on B Detail | Fixed in branch for explicit stop, inactivity, and max duration; reducer summary semantics for overlapping views remain under investigation |
| Session Replay | Recorder/context mapping may follow an arbitrary scene's key window | First key window across an unordered scene set; one coordinator | Two-window iPadOS 26.5 probe uploaded replay payloads without an SDK crash | Not required for core RUM support | Out of scope except crash safety; coexistence smoke passes, broader crash regression remains |
| WebView correlation | Browser events can be stitched to another scene's native container | Branch carries private source-scene metadata and queries scene-keyed view history | Pending fixed-runtime rerun | Pending | Fixed in branch; three focused tests pass |
| Profiling | Profile-level RUM attributes are last-writer-wins across views | One mutable correlation snapshot | Pending | Pending | Confirmed by source |
| Crash/fatal context | Any view update can overwrite one process crash context | Branch restricts updates to the representative and restores another active scene when needed | Pending | Pending | Fixed to representative policy; focused tests pass |
| App/scene lifecycle | Per-scene transitions are invisible to view ownership | Branch observes background, foreground, and disconnect per scene | Pending fixed-runtime rerun | Pending | Fixed in branch; focused tests pass |

## Experimental application plan

The probe must use the SDK sources in this checkout and real local RUM
configuration. Every run will use a unique run identifier attached to events so
that console output, locally observed payloads, and backend sessions can be joined
without relying on timestamps alone.

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
- Finish UIKit and SwiftUI tap/scroll attribution plus disconnect coverage. Action
  timeout/stop ownership, duplicate identities, session rollover, and restoration
  now have focused coverage; retain them as regression gates.
- Preserve the legacy no-scene and single-scene paths without meaningful hot-path
  overhead.
- Gate the hidden SwiftUI scene reader and UI-event-only causal instrumentation
  behind the configured bundle's explicit multi-scene declaration. Normal apps
  retain the original direct modifier lifecycle and swizzling conditions.
- For iOS 17+, experiment with an internal custom `UITraitDefinition` bridged by
  `UITraitBridgedEnvironmentKey`, seeded from each real `UIWindowScene`. Verify
  its value inside customer outer lifecycle callbacks before treating it as the
  missing early provenance. Availability-gate the mechanism so the SDK remains
  compatible with its iOS 15 deployment target, but do not build a separate
  iOS 15/16 multi-scene integration or infer a scene from global/window ordering.
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
  covered for both Logs and Trace; accepted/rejected and 100 ms expiry boundaries
  still require the split live probe.

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

These rules improve correctness after an owner is already known and do not claim
that the SDK can discover a scene for arbitrary work.

### 4. Defer explicit customer attribution contracts

An explicit resolver is not required for the current support goal. Source-less
work retains the last-interacted representative for compatibility. Keep these as
future options only if customer evidence later justifies deterministic attribution:

- A fast, thread-safe request-start Resource context resolver receiving the
  `URLRequest`, any automatic origin, and all active candidates. Each candidate
  would contain an opaque scene/session identity, view ID/name/path, relevant
  view context, and a valid current action. It would return one candidate or nil
  for shared/unknown work. Product review must decide whether this is fallback-only
  or may override automatic provenance, and it must not overload the existing
  completion-time `resourceAttributesProvider` contract.
- A general scoped RUM-context API for manual spans, logs, operations, and other
  work. A Resource-only resolver cannot make those surfaces deterministic.

Both require RFC/product review before any public API is introduced. Do not spend
this project on an iOS 15/16 escape hatch or add either API speculatively. Neither
can invent causality when request metadata and application context do not
distinguish a scene.

### 5. Validate, simplify, and regress

- Run the full causal-boundary matrix on the two-window probe and inspect backend
  Resources and Spans.
- Remove speculative machinery that does not move a supported case from wrong to
  correct.
- Rerun complete RUM, Internal, Logs, Trace, and WebView suites, plus legacy
  single-window integration flows and URLSession custom-handler behavior.
- Treat Session Replay as crash-safety coexistence only.
- Update this assessment with exact supported, partial, ambiguous, and unsupported
  surfaces before proposing a release contract.

## Working policies and product decisions

1. **Working policy:** a source-less manual API uses the most recently interacted
   representative view. It is emitted once, never broadcast. This is the approved
   compatibility fallback for the current project.
2. **Working policy:** entering the background ends that scene's visible RUM view;
   foregrounding restarts it. Merely losing focus while still visible does not.
3. **Working policy:** concurrent views overlap inside one application RUM session.
   Backend/UI acceptance of overlapping active views still needs validation.
4. **Working policy:** process-wide long tasks, hangs, memory warnings, and crashes
   emit once against the last-interacted representative. CPU/memory/display samples
   remain per-visible-view summaries of shared process/render-loop data. Confirm
   whether any event requires a different policy.
5. **Decision for this work:** Session Replay does not need correct multi-window
   recording yet. It must coexist without crashing or destabilizing base RUM.
   Scene-keyed window selection, RUM context, touch buffering, scheduling, and
   snapshot state remain future Replay work and do not block base-RUM support.
6. **Product decision:** generic unknown-provenance work inherits the most recently
   interacted process representative. This volume-preserving fallback can be
   inaccurate and must not be presented as exact ownership.
7. **Deferred API option:** a request-start Resource resolver or general scoped
   RUM-context API may be revisited with customer evidence. Neither is needed for
   iPhone Duo support and neither is authorized for implementation without the
   normal contract, performance, Objective-C, and RFC review.
8. **Product decision:** iPhone Duo on iOS 27.1 is the release target. Correct
   behavior on older multi-scene systems is useful but does not gate support.
   Normal and single-scene apps on the SDK's older deployment targets must still
   avoid regression.
9. **Product decision:** on the supported OS range, transparent SwiftUI tracking
   should establish the destination RUM view before outer `.onAppear` and the
   synchronous prefix of `.task` when that can be achieved without compromise.
   No equivalent guarantee is required for iOS 15/16.

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
  with their resulting RUM view identifier and name. The next gate is compiling
  the complete probe, then correlating these records with backend events.
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
  delivery outlives the captured view, exact-view routing deliberately falls
  back to the representative branch; two scope tests verify that delayed errors
  and resources retain the legacy no-drop behavior, including completion on a
  pending resource's actual owner. This aligns the log and mirrored RUM error
  when the originating concurrent window is still present without degrading the
  sequential-navigation fallback.
- Manual and OpenTelemetry spans freeze the RUM context selected at span creation,
  but the process-wide exported context is not necessarily their originating
  scene. Trace-only URLSession spans are created at completion with an earlier
  start timestamp, so the experiment captures a request-start selection and
  supplies it to the late writer. Four Trace tests prove that supplied A/B
  selections survive reverse completion and later representative changes. They
  do not prove that a generic request automatically selected A or B correctly.
  Requests tracked as RUM resources still avoid duplicate client spans as before.
- Feature operations with a unique `name` plus `operationKey` now remember the
  scene that owned their start and resolve every later step against that scene's
  current view. This permits navigation A1 -> A2 during an operation while an
  interaction makes B process-representative: start remains on A1 and end lands
  on A2. The same selected view is used for the operation vital, its containing
  view update, and the profiling operation message. The focused multi-scene test
  and three manager regressions pass. Identical name/key pairs remain one
  operation by backend contract and still warn/restart rather than being silently
  rewritten with scene identity.
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
- Do not invent a provisional scene ID or rebind an existing RUM view piecemeal.
  Ownership is immutable across the view scope, INV tracker, cache, operations,
  lifecycle maps, and snapshots; ordinary stop/start also allocates a new view ID.
- After activating the other Device Hub window, refresh the accessibility tree
  before addressing an element by index. A cached B button can still invoke B's
  controller while the screenshot visibly shows A, leaving the representative
  unchanged and invalidating a delayed-provenance experiment.

## Completion gates

The assessment can change to supported only when:

- concurrent UIKit and SwiftUI windows keep independent, correct view lifetimes;
- navigation and actions are attributed to their originating windows;
- bounded Resource/Trace provenance is validated with actual URLSession timing,
  while unknown-provenance work is explicitly classified and follows the approved
  last-interacted representative fallback;
- RUM Resource and Trace freeze and share one request-start selection whenever a
  trustworthy owner exists, including navigation, rollover, reverse completion,
  and scene closure;
- operations, errors, vitals, and fatal/exported context have explicit support
  levels and no silent misattribution claims; Session Replay coexists without a
  crash even though scene-correct replay is not claimed;
- scene lifecycle transitions do not disturb unrelated windows;
- tests cover duplicate identities, disconnect, restoration, session expiration,
  and foreground/background transitions;
- single-scene and legacy lifecycle tests demonstrate no regression;
- the iPad probe and backend session both confirm the intended model, followed by
  iPhone Duo validation on iOS 27.1 when that runtime is available.
