# Native SwiftUI multi-scene probe

This standalone iOS 27 app isolates Datadog RUM automatic SwiftUI tracking from
the UIKit lifecycle used by the integration-test Runner. It exercises a typed
`WindowGroup`, a bound `NavigationStack`, and `openWindow` without adding a target
to the repository's main Xcode project.

The app reads `DATADOG_CLIENT_TOKEN` and `RUM_APPLICATION_ID` through the existing
`xcconfigs/Datadog.xcconfig` setup. Do not copy those values into this directory.

## Generate and run

Regenerate the project after changing `project.yml`:

```sh
cd Datadog/Example/MultiSceneProbe
xcodegen generate --spec project.yml
```

Open `RUMNativeMultiSceneProbe.xcodeproj`, select an iPadOS 27 simulator, and pass
the stable scenario arguments through the scheme or launch command:

```text
--probe-scenario swiftui.stack.return
--probe-run-id <unique-run-id>
--probe-run-mode clean
```

`--probe-run-id` is generated when omitted, but an explicit value is recommended
for joining console, payload, and backend evidence. Run mode is `clean` or
`restoration`; each scenario supplies a default. Unknown arguments, unknown
`DD_MULTI_SCENE_*` keys, invalid values, and contradictory configurations are
rejected before Datadog starts. The complete resolved manifest is always the
first `RUM Native Multi-Scene JSONL` record. A rejected launch renders a
configuration-error screen and produces no RUM session.

The in-app `--probe-run-mode clean` value does not uninstall the bundle or clear
host state before launch. For an acceptance run, explicitly uninstall the probe
from the destination first. Back-to-back Xcode install/run calls can leave new
view documents carrying the preceding run's global `context.probe.run_id` even
when later actions and Resources use the new ID (`EXP-117`). Treat such a run as
local-only evidence and rerun it after uninstalling.

The catalog currently preserves these experiment families:

| Scenario | Evidence preserved | Execution level |
| --- | --- | --- |
| `interactive.manual` | Interactive automatic-tracking control | Existing UI controls |
| `swiftui.automatic.single-window` | `EXP-027` | Existing deterministic automation |
| `swiftui.automatic.two-window` | `EXP-028` | Existing deterministic automation |
| `swiftui.stack.occurrence-push` | `EXP-090` setup | Existing deterministic automation |
| `swiftui.stack.return` | `EXP-098`, `EXP-099`, `EXP-109`, `EXP-115`, `EXP-116` | Signal-driven PASS, including automatic-plus-explicit coexistence and the once-per-container wrapper |
| `swiftui.stack.abort` | `EXP-091`, `EXP-110`, `EXP-116` | Signal-driven PASS through route-owned and container-wrapper paths |
| `swiftui.stack.same-type-replacement` | `EXP-090`, `EXP-110`, `EXP-116` | Signal-driven PASS through route-owned and container-wrapper paths |
| `swiftui.stack.different-type-replacement` | `EXP-054`, `EXP-110` | Signal-driven PASS |
| `swiftui.coexistence.semantic-a-automatic-b` | `EXP-118` | Signal-driven; simulator-inconclusive, physical hardware required |
| `swiftui.coexistence.automatic-manual-sheet` | `EXP-119` | Signal-driven FAIL: immediate `onDismiss` work retains outgoing Sheet; settled work uses fresh automatic Home |
| `swiftui.coexistence.automatic-scene-targeted-sheet` | `EXP-123`–`EXP-125` | Handler-only baseline FAIL; suppression-bound successor PASS 14/14 with semantic Sheet, no automatic duplicate, and fresh Home before immediate dismiss work |
| `swiftui.coexistence.automatic-scene-targeted-full-screen-cover` | `EXP-126` | Independent signal-driven PASS 14/14 with semantic full-screen cover, no automatic duplicate, and fresh Home before immediate dismiss work |
| `swiftui.coexistence.sibling-container-authority` | `EXP-127` | Signal-driven PASS 19/19; real left/right controller ancestries prove container-local authority and latest right-Detail reveal |
| `swiftui.coexistence.automatic-keyed-manual-view` | `EXP-120`–`EXP-122` | Legacy direct-command baseline FAIL; internal exact-scene successor PASS 16/16 with authoritative Compose and fresh Home H2 |
| `swiftui.coexistence.nested-keyed-manual-view` | `EXP-128` | Signal-driven PASS 29/29; Compose C1 → Preview P1 → fresh Compose C2 → fresh Home H2, with duplicate Compose start crash-safe and restart-free |
| `swiftui.coexistence.same-key-manual-two-scenes` | `EXP-129` | Hostless contract PASS 91/91; clean simulator run reached both scenes but expired before manual starts, so live acceptance requires iPhone Duo or physical iPad |
| `operations.navigation.lifecycle` | `EXP-130` | Signal-driven PASS 27/27; backend raw steps and reduced Operations prove independent start/end view attribution across same-scene navigation, failure, and duplicate-start orphan semantics |
| `operations.cross-scene.lifecycle` | `EXP-131` | Hostless contract PASS 100/100; exact A→B success/failure and distinct-key reverse-completion oracle prepared, with live acceptance reserved for iPhone Duo or physical iPad |
| `swiftui.stack.manual-sheet-return` | `EXP-040` | Observable driver pending |
| `swiftui.stack.native-pop-cancel`, `swiftui.stack.native-pop-finish` | `EXP-100` | Prepared; hardware or human gesture required |
| `swiftui.split.automatic-baseline` | `EXP-069`, `EXP-111` | Signal-driven FAIL: no semantic destination views |
| `swiftui.split.same-type-selection` | `EXP-102`, `EXP-111` | Signal-driven PASS |
| `swiftui.split.same-type-selection-two-scenes` | `EXP-103` | Existing deterministic automation; simultaneous topology remains unproven |
| `swiftui.split.retained-return` | `EXP-105`, `EXP-111` | Signal-driven PASS |
| `swiftui.split.empty-selection` | `EXP-087` | Existing deterministic control |
| `uikit.split.replacement`, `uikit.split.subclass` | `EXP-080`, `EXP-072` | Existing deterministic automation |
| `uikit.split.pop-automatic` | `EXP-079` | Existing deterministic automation |
| `uikit.split.pop-cancel`, `uikit.split.pop-finish` | `EXP-083`, `EXP-084`, `EXP-112` | Signal-driven PASS |
| `uikit.split.native-pop-control`, `uikit.split.native-pop-cancel`, `uikit.split.native-pop-finish` | `EXP-081`, `EXP-082` | Prepared; cancellation needs hardware or human input |
| `uikit.split.concurrent-scenes` | `EXP-086` | Existing automation; simultaneous topology remains unproven |
| `windows.parallel-navigation` | `EXP-033`, `EXP-059`, `EXP-103` | Existing automation; simultaneous topology remains unproven |
| `windows.close-with-resource` | `EXP-041`, `EXP-113` | Signal-driven PASS; simultaneous-visible peer proof needs hardware |
| `windows.activation-sequence` | `EXP-114` | Signal-driven and fail-closed; current simulator is INCONCLUSIVE, capable hardware required |
| `actions.exact-source-handoff` | `EXP-089` | Existing filtered control; discriminator needs simultaneous topology |
| `swiftui.reader.synthetic-reconnect`, `swiftui.reader.synthetic-reconnect-scene-b` | `EXP-066` | Existing synthetic control |
| `windows.restoration` | `EXP-042` | Prepared; concurrent restoration needs hardware or human setup |
| `diagnostic.swiftui.offscreen-tab` | `EXP-036` | Existing diagnostic control |
| `diagnostic.swiftui.navigation-path.same-type-replacement`, `diagnostic.swiftui.navigation-path.split-selection` | `EXP-057`, `EXP-068` | Superseded diagnostic controls retained for reproduction |
| `regression.single-scene` | `EXP-026`, `EXP-032` | Existing deterministic automation |

The scenario manifest already models ordered steps, signal waits, completion
conditions, required capabilities, and the expected semantic timeline. The app
now records versioned JSONL probe signals and mapper-observed RUM snapshots. A
pure reducer derives first-observed starts and active-to-inactive stops, and the
semantic oracle returns only `PASS`, `FAIL`, `SKIPPED`, or `INCONCLUSIVE`. Its
fixtures cover correct Home return, wrong-view attribution, asynchronous
view-stop/Resource observations, repeated-name completion, a missing event, a
forbidden view, and an ignored native gesture. An exact main-actor scene
registry adds stable logical/native identity, weak window ownership, readiness,
activation, geometry, route, and disconnect generations without serializing its
future Execution Context seam. The generated test plan passes 100/100. The stack
return, abort, replacement, split-selection, and deterministic UIKit transition
scenarios, plus exact scene open/close/activation, drive their exact scene and wait for
observable readiness, lifecycle state, path/selection,
destination, transition, and RUM-occurrence signals, acknowledge every step, and
emit exactly one final result. The terminal JSON result is also written through
OSLog so it survives an expired Xcode console session. Clean iPadOS 27 semantic
runs pass locally and in backend intake (`EXP-109` through `EXP-113`); `EXP-115`
also passes with automatic and explicit SwiftUI tracking enabled together and no
duplicate view. `EXP-116` passes return, abort, and same-type replacement after
moving the path and route metadata to one probe-container call site. The wrapper
still owns the root and typed destination builders so it can install the early
tracking boundary at each materialized route; a passive root-only modifier is
known to be too late. This is an API-shape prototype, not a shipped integration.
`EXP-119` adds one explicit Sheet over an otherwise automatic hierarchy. It
proves automatic Home H1 -> explicit Sheet S1 -> fresh automatic Home H2 without
an automatic Sheet duplicate, but intentionally fails while immediate
`onDismiss` work still owns S1 before H2 starts. Do not treat the later settled
H2 attribution as closing that boundary.
`EXP-123` routes the complete semantic Sheet destination through the exact-scene
manual stack and proves handler authority alone does not deduplicate the native
presentation host. `EXP-124` adds a suppression-only boundary and produces the
right H1/M1/H2 owners, but exposes a harness mistake: a pending Resource can
delay M1's final aggregate snapshot after semantic stop. `EXP-125` separates the
semantic authority interval from the mounted presentation-subtree interval and
passes 14/14 locally and in backend intake. It contains no automatic Sheet;
active work owns M1 and immediate plus settled dismiss work owns fresh H2. The
independent `EXP-126` scenario repeats that strict contract for
`fullScreenCover`: it passes 14/14 locally and in backend intake, creates no
automatic `ProbeFullScreenCoverView`, and assigns immediate plus settled dismiss
work to one fresh Home H2.
`EXP-127` mounts two sibling `NavigationStack` branches below one outer SwiftUI
host. A probe-only controller-ancestry reader must prove that left authority and
right Home/Detail use distinct navigation branches before the scenario can pass;
missing topology is `INCONCLUSIVE`. Left manual M1 remains current while right
Detail commits underneath it, and exact stop reveals only one fresh Detail before
immediate and settled work. The first run exposed the ancestry reader itself as a
late automatic RUM view, so automatic discovery now excludes only that exact
measurement type. Two clean successors contain no helper view and pass 19/19;
the final backend session has four views and 11 correctly owned action/Resource
pairs with zero errors or crashes.
`EXP-120` starts and stops a direct keyed Compose view over automatic Home. Its
step-bounded authority interval and exact owner relations catch automatic
preemption even when Compose starts and stops before the driver can wait for it.
The legacy direct-command baseline fails because an automatic fallback displaces
Compose within 31–48 ms and owns active/immediate action/Resource pairs; only
settled work belongs to fresh Home H2. `EXP-121` switches the probe to the
internal exact-scene stack route and proves Compose authority, while exposing a
generic fallback revealed at stop. `EXP-122` hardens that path and passes 16/16:
no intervening generic fallback, active work on Compose M1, and immediate plus
settled return work on the same fresh Home H2. Do not add a Compose-view wait as
a barrier or treat deferred mapper stop ordering as navigation order. This probe
uses an internal capability; customer-facing scene overloads still require API
review.
`EXP-128` extends that exact-scene path to a real keyed manual suffix. Its clean
run creates automatic Home H1, Compose C1, Preview P1, fresh Compose C2 after the
Preview stop, and fresh automatic Home H2 after the Compose stop. A duplicate
active Compose start changes no probe destination and creates no RUM occurrence;
its action/Resource remains on C2. The first attempt timed out because the C1
mapper snapshot arrived before the driver began waiting. Exact `rum-view` waits
now search already-recorded immutable evidence before subscribing, and the retry
passes 29/29 locally and in backend intake with no error or crash.
`EXP-129` uses a harness-only exact scene-context marker to model work invoked
from a trustworthy UI-event call site while leaving ordinary source-less marker
behavior unchanged. It starts the same `compose` key in A and B, stops B before
A, and requires distinct Compose owners, continued A authority after B stops,
and fresh returned Home owners in both scenes. Adversarial fixtures reject shared
UUIDs and cross-scene stop or work leakage. The clean iPad simulator run reached
both native scenes, then the Xcode/device session expired before manual authority
began. It emitted no terminal result or backend event, so run this exact named
scenario on capable hardware rather than treating the hostless contract as live
acceptance.
`EXP-130` exercises Operations across six fresh single-scene navigation
occurrences without pretending mapper assertions are Operation telemetry. The
local driver proves every API invocation happened from the intended scene and
destination. Backend raw `operation_step` intake then proves success from Home H1
to Detail D1, failure from Home H2 to Detail D2, and duplicate start from Home H3
to Detail D3 followed by success on the latest D3 start. The earlier H3 duplicate
start remains an unclosed raw backend operation as specified; no synthetic end,
error event, or app/SDK crash was observed. Cross-scene completion and the public
view-targeting API remain separate gates.
`EXP-131` isolates the remaining cross-window Operation contract without adding
navigation already covered by `EXP-130`. It starts success and failure in A and
completes them in B, then starts distinct `parallel-alpha` and `parallel-beta`
instances in A and B and completes B before A. The hostless oracle rejects shared
A/B view IDs, wrong-scene B work, a B completion on A, and A owner drift after B
completes. No local signal is treated as Operation telemetry. The exact scenario
must still produce eight raw steps and four reduced Operations on capable
multi-window hardware.
`EXP-118` installs that semantic boundary only in scene A while leaving scene B
automatic. Its oracle separates source labels from mapper ownership and rejects
an automatic owner first observed before B opened. Two clean simulator prefixes
kept A exact and created B's independent automatic views, but simulator
`backboardd` aborted before the decisive B marker and terminal result. Finish the
prepared scenario on iPhone Duo or a physical multi-window iPad; it is not yet an
acceptance pass. The
activation row remains explicitly inconclusive on the current simulator
(`EXP-114`). The automatic SwiftUI split control
executes the same selection steps but fails because it emits internal container
views instead of semantic selections. Other scenarios remain at the execution
level shown in the table; a modeled timeline or partial live prefix is not itself
a local PASS.

Probe call-site context and RUM ownership are intentionally separate. Source
labels say where the harness invoked work; only mapper-observed RUM view UUIDs and
scene metadata establish attribution. Mapper callbacks occur before persistence
and upload, so mapper agreement still requires backend confirmation. The first
structured Home-return acceptance set has that confirmation for distinct
Home₁ → Detail → Home₂ occurrences and post-return work on Home₂.

## Observable driver

`swiftui.stack.return`, `swiftui.stack.abort`,
`swiftui.stack.same-type-replacement`, and
`swiftui.stack.different-type-replacement`, plus
`swiftui.split.automatic-baseline`, `swiftui.split.same-type-selection`, and
`swiftui.split.retained-return`, plus `uikit.split.pop-cancel` and
`uikit.split.pop-finish`, plus `windows.close-with-resource` and
`windows.activation-sequence`, plus
`swiftui.coexistence.sibling-container-authority` and
`swiftui.coexistence.nested-keyed-manual-view`, use the
signal-driven execution loop.
They do not use arbitrary navigation delays: the driver waits for scene readiness,
route mutation, destination materialization, and expected mapper-observed RUM
occurrences before advancing. The abort timeline forbids a speculative Detail;
replacement timelines require the decisive action and Resource on the new
occurrence. View-stop mapper snapshots may arrive after the next view starts
during a SwiftUI animation, and Resource mapper callbacks occur when work
completes. Both are required eventual facts rather than navigation-order clocks;
Resource ownership must still match the view captured at start. Ordered view
starts and actions remain strict. Completion conditions scan past earlier
same-named occurrences so a returned destination can satisfy an
occurrence-specific condition.

An `open-window` step names its exact source in `scene` and exact target in
`value`. The driver dispatches only through the source scene's registered
executor, then acknowledges the command only after the target emits
`scene-ready`. A `close-window` step dispatches through the target scene's exact
executor and waits for that same scene's disconnect generation before continuing.
It never selects a scene from unordered application session collections. In
`EXP-113`, A opened B, B emitted `before-close`, B disconnected, and A then
emitted `after-peer-close` without replacing A's original Home occurrence.
An `activate-window` step dispatches only through its exact registered
`UIWindowScene` and acknowledges that target's foreground-active state. The
activation sequence then requires the peer's latest non-superseded lifecycle
state to be background before emitting or judging a marker. This is a latched
state condition, so either notification order is valid; a missing transition is
`INCONCLUSIVE`, not an attribution failure. A source label on a plain manual RUM
call is probe metadata and does not provide SDK provenance, so such work continues
to follow the last-interacted representative. The current simulator kept both
scenes active and later crashed `backboardd` during rapid activation; run this row
on iPhone Duo or a physical multi-window iPad (`EXP-114`).

The UIKit transition driver separately begins a real
`UIPercentDrivenInteractiveTransition`, observes its accepted coordinator,
advances it to the requested percentage, requests cancellation or completion,
and waits for the coordinator's actual result. Cancellation keeps the original
Secondary 2 RUM UUID; completion creates a fresh returned Secondary 1 UUID. Each
result also requires an action and Resource on the resolved occurrence. Primary
lifecycle remains visible to the probe, but the iOS 27 multi-scene SDK path no
longer turns a regular-width structural Primary into a RUM view (`EXP-112`).

Run each acceptance attempt after uninstalling the probe, with a unique run ID
and `--probe-run-mode clean`, then join its JSONL and backend query by that ID.
The programmatic driver validates SDK occurrence and attribution semantics; it is
not evidence for native interactive gestures. Those scenarios remain manual and
`INCONCLUSIVE` until a recognized path/coordinator transition is observed on
appropriate hardware or through human input.

## Legacy environment adapter

The environment-variable surface is temporary. It accepts only exact profiles
that normalize to one legacy-compatible named scenario; arbitrary Boolean
combinations no longer run. Do not mix these variables with
`--probe-scenario`.

```text
DD_MULTI_SCENE_RUN_ID=<unique-run-id>
DD_MULTI_SCENE_SWIFTUI_VIEW_TRACKING=automatic
DD_MULTI_SCENE_SWIFTUI_STRESS=none
DD_MULTI_SCENE_AUTORUN_SWIFTUI_DETAIL=1
DD_MULTI_SCENE_AUTORUN_OPEN_SECOND_WINDOW=1
DD_MULTI_SCENE_AUTORUN_CLOSE_SCENE_B=0
DD_MULTI_SCENE_AUTORUN_ABORT_DETAIL=0
DD_MULTI_SCENE_AUTORUN_REPLACE_DETAIL=0
DD_MULTI_SCENE_AUTORUN_REPLACE_DETAIL_INSTANCE=0
DD_MULTI_SCENE_FORCE_ROUTE_IDENTITY=0
DD_MULTI_SCENE_SWIFTUI_LAYOUT=stack
DD_MULTI_SCENE_UIKIT_SPLIT_AUTOMATIC_POP=1
DD_MULTI_SCENE_UIKIT_SPLIT_INTERACTIVE_POP=none
DD_MULTI_SCENE_SPLIT_INITIAL_SELECTION=detail-1
DD_MULTI_SCENE_SPLIT_AUTOMATIC_SEQUENCE=1
DD_MULTI_SCENE_SPLIT_RETURN_TO_DETAIL=0
DD_MULTI_SCENE_UI_EVENT_HANDOFF=0
DD_MULTI_SCENE_SYNTHETIC_READER_DISCONNECT=none
```

Set `DD_MULTI_SCENE_AUTORUN_OPEN_SECOND_WINDOW=0` for the single-window control.
Set `DD_MULTI_SCENE_SWIFTUI_VIEW_TRACKING=manual` to disable automatic SwiftUI
view discovery and apply the existing `trackRUMView` modifier to Home, Detail,
Alternate, and Sheet.
Set it to `navigation-path` for the probe-only route-owned prototype. That mode
disables controller discovery, places the existing explicit modifier directly at
the Home, Detail, and Alternate content boundaries, and records authoritative
typed-path mutations for correlation. It does not treat every write as a committed
occurrence or serialize a counter because SwiftUI can coalesce writes and retain
earlier screen values; the RUM view UUID is the occurrence identity. It is not
proposed public API and does not cover the sheet path. It exists to validate
ordering, occurrence, and cancellation semantics before RFC/API review.
Set it to `navigation-occurrence` for the Debug-only keyed integration probe.
This route-owned mode supplies the SDK with an opaque occurrence plus the bound
navigation mutation generation while leaving the tracked customer content's
SwiftUI identity unchanged. It records stable witnesses for Home across pop
cancellation/completion, for retained stack Detail values, and for retained split
Detail selection across Detail 1 -> Detail 2 replacement. It also leaves
`DefaultSwiftUIRUMViewsPredicate` enabled so the probe exercises the approved
coexistence rule: an active explicit subtree is authoritative without globally
disabling automatic tracking or producing a duplicate automatic view. In this mode
`DD_MULTI_SCENE_FORCE_ROUTE_IDENTITY=1` is intentionally ignored, so a passing
run cannot be explained by the old full-content `.id(route)` control.
`automatic` remains the default failing baseline.

For acceptance, `Home → Detail → Home` must produce three RUM view UUIDs,
including two distinct Home UUIDs even when SwiftUI retains the same Home state.
A cancelled transition must produce no additional RUM view.
Set `DD_MULTI_SCENE_AUTORUN_ABORT_DETAIL=1` with automatic Detail and second-window
opening disabled to write `[.detail(1)]` and then `[]` in the same task turn. The
binding writes are logged as mutations, not committed occurrences. If SwiftUI
coalesces them without showing Detail, RUM must keep the original Home UUID and
attribute the `post-aborted-navigation` marker to it.
Set `DD_MULTI_SCENE_AUTORUN_REPLACE_DETAIL=1` with automatic Detail enabled to
keep Detail visible for one second and then replace `[.detail]` with
`[.alternate]`. The expected semantic path is `Home → Detail → Alternate`, with
one UUID per occurrence and no intermediate Home view.
Set `DD_MULTI_SCENE_AUTORUN_REPLACE_DETAIL_INSTANCE=1` instead to replace
`[.detail(1)]` with `[.detail(2)]`. Both destinations use the same SwiftUI view
type and RUM view name. The expected semantic path is
`Home → Detail₁ → Detail₂`, with distinct Detail UUIDs and no intermediate Home;
this detects accidental coupling between a RUM occurrence and retained SwiftUI
or platform identity. Do not enable both replacement modes in the same run.
The baseline deliberately leaves `DD_MULTI_SCENE_FORCE_ROUTE_IDENTITY=0`. Set it
to `1` only for the probe control that applies `.id(route)` around the tracked
destination. A passing control proves that an explicit occurrence identity is
the missing input; it does not make `.id` the proposed customer API because that
modifier also changes the application's own SwiftUI state lifetime.
Set `DD_MULTI_SCENE_SYNTHETIC_READER_DISCONNECT=scene-A` or `scene-B` only for
the retained-reader fault-injection control. After the selected scene reaches
Detail, the probe posts `UIScene.didDisconnectNotification` for its still-live
`UIWindowScene`, updates a probe generation value so SwiftUI reuses and updates
the existing scene-identifier reader, and emits a post-update marker. This
exercises SDK notification teardown and retained-reader remount integration. It
is deliberately synthetic: the scene remains connected and active, so a passing
run is not evidence that iPadOS disconnected and reconnected the scene.
Set `DD_MULTI_SCENE_SWIFTUI_LAYOUT=split-selection` for the regular-width
`NavigationSplitView` selection control. It waits for scene resolution, starts
on Detail 1, then commits Detail 2 using the same destination type, followed by
a different-type Placeholder. Each materialized selection emits an immediate
`selection-committed` action/resource marker. A co-located UIKit witness records
whether SwiftUI retained the Detail platform object; it is evidence about the
content boundary, not direct access to the SDK's private tracking representable.
With `navigation-path` tracking and route identity disabled, the same-type
Detail 1 -> Detail 2 change is the retained-reader failing baseline. Enabling
`DD_MULTI_SCENE_FORCE_ROUTE_IDENTITY=1` applies the same probe-only `.id(route)`
control, but also resets customer content lifetime. With
`navigation-occurrence`, the required RUM chain is
`Detail₁ → Detail₂ → Placeholder`, each with a distinct UUID and without an
intervening Sidebar or Home, while the Detail witness remains unchanged. The
sequence is skipped in compact width.
Set `DD_MULTI_SCENE_SPLIT_RETURN_TO_DETAIL=1` to extend that sequence to
`Detail₁ → Detail₂ → Placeholder → Detail₂(returned)`. The returned Detail must
receive a fresh UUID before its immediate marker while preserving the same Detail
witness. This specifically exercises early reveal of an inactive retained split
route; a repeated Detail name or occurrence key does not permit UUID reuse.
Set `DD_MULTI_SCENE_SPLIT_INITIAL_SELECTION=none` and
`DD_MULTI_SCENE_SPLIT_AUTOMATIC_SEQUENCE=0` for the empty-detail control. It must
not manufacture a Detail occurrence before the customer selects one.
Set `DD_MULTI_SCENE_SWIFTUI_LAYOUT=uikit-split` for the stock
`UISplitViewController` mirror. It first materializes an application Primary
controller, then installs Secondary 1, and finally replaces it with a fresh
same-class Secondary 2 while Primary remains visible. Each child records UIKit
containment and appearance lifecycle events and emits a post-materialization
action/resource marker. Primary lifecycle remains recorded as structural
diagnostic input, but the approved RUM model exposes one current destination per
scene. The required RUM occurrence order is therefore
`Secondary₁ → Secondary₂`, with no Primary RUM view. Historical
`EXP-080` evidence contains an initial Primary and proves only that the branch no
longer restarts it between secondaries. `EXP-112` removes that structural Primary
from the current iOS 27 multi-scene path. Use `uikit-split-subclass` only as the
follow-up control that swaps the stock container for an application subclass;
this reveals whether the container itself becomes an extra automatically tracked
RUM view.
Set `DD_MULTI_SCENE_SWIFTUI_LAYOUT=uikit-split-navigation` for the stock split
navigation control. It keeps one secondary `UINavigationController`, installs
Secondary 1 as its stable root, pushes a fresh same-class Secondary 2, and pops
back to the same Secondary 1 controller. The required occurrence order is
`Secondary₁ → Secondary₂ → Secondary₁`, with a fresh UUID for the returned
Secondary 1 and no Primary RUM occurrence. Historical `EXP-079` and
`EXP-082` through `EXP-084` retain an initial structural Primary and remain
failure evidence for the old path, while their fresh returned-Secondary and
cancellation behavior remain valid. `EXP-112` reruns the deterministic
cancel/finish pair without any Primary RUM occurrence.
Set `DD_MULTI_SCENE_UIKIT_SPLIT_AUTOMATIC_POP=0` to leave Secondary 2 visible
after the automatic push. This probe-only gate permits an interactive edge-pop
gesture to be cancelled or completed without racing the scheduled pop. A
cancelled gesture must retain the original Secondary 2 RUM UUID; a completed
gesture must start a fresh Secondary 1 occurrence and must not expose Primary.
When a straight simulator gesture cannot arbitrate against the split divider,
set `DD_MULTI_SCENE_UIKIT_SPLIT_INTERACTIVE_POP=cancel` or `finish`. The probe
then drives a real `UIPercentDrivenInteractiveTransition` through 35 percent and
resolves it with the requested outcome. This deterministic public-UIKit control
exists only to validate lifecycle and RUM semantics; it is not SDK behavior.
Set `DD_MULTI_SCENE_UI_EVENT_HANDOFF=1` to add an “Emit scoped manual marker”
button to each UIKit split child. The probe enables automatic UIKit actions but
deliberately filters this button from action recording. A physical tap still
provides the SDK with the source scene and exact view while UIKit synchronously
dispatches the target action. The callback emits one synchronous manual action
and resource, followed by another pair after the UI-event scope ends. In a
two-window run where another scene remains the process representative, the
synchronous pair must use the tapped scene's exact current view; the delayed
pair must use the newly last-interacted tapped view after the exact action updates
the process representative. No automatic
tap action should be emitted for the filtered control.
For any split layout, `DD_MULTI_SCENE_AUTORUN_OPEN_SECOND_WINDOW=1` opens scene B
from scene A one second after scene resolution. Both scenes then run their own
split sequence, allowing pending transitions and occurrence ownership to overlap.
The Home screen also exposes a tracked SwiftUI sheet and a manual current-view
marker. Together they validate `Home₁ → Sheet → Home₂` occurrence identity and
post-dismiss attribution without relying on platform-object replacement.
Set `DD_MULTI_SCENE_AUTORUN_CLOSE_SCENE_B=1` to dismiss scene B shortly after
its root task starts. Open B manually with automatic detail/window opening off to
isolate early scene teardown while scene A remains active.
Set `DD_MULTI_SCENE_SWIFTUI_STRESS=tab-preload` to place the normal navigation
content beside an explicitly tracked, initially unselected tab. This detects
whether a tracking candidate mistakes offscreen platform-view construction for
semantic appearance; leave the offscreen tab unselected during that run.
Uninstall the probe before a clean run so restored scene sessions cannot change
the startup sequence.

The deterministic flow is:

1. scene A Home emits `.onAppear`, immediate `.task`, and delayed `.task` markers;
2. scene A navigates to Detail and emits the same markers;
3. the two-window mode opens scene B through `openWindow`;
4. scene B repeats Home -> Detail.

Each marker emits one custom action and one short manual resource. Attributes
include `probe.run_id`, `probe.source_scene`, `probe.scene_session_id`,
`probe.screen`, and `probe.phase`; these describe the source call site, not proof
of RUM ownership. Tracked-view records use the separate `probe.view.*` namespace.
Event mappers print the RUM session, view, action, and resource IDs selected by the
SDK. Query ingested events with:

```text
@context.probe.run_id:<unique-run-id>
```

## Current failing baseline

The first native runs on iPadOS 27 established two distinct problems:

- SwiftUI lifecycle work precedes transparent destination-view discovery even in
  one window. Home starts on `ApplicationLaunch`; Detail remains on the preceding
  `NavigationStackHostingController<AnyView>` until `ProbeDetailView` appears
  later. `ProbeHomeView` is never emitted as an automatic RUM view.
- When scene B opens while scene A is on Detail, B Home `.onAppear` and immediate
  `.task` work are attributed to scene A's `ProbeDetailView`. B obtains its own
  navigation-host view only afterward.

Exact run and session IDs belong in the
[experiment history](../../../DatadogRUM/MultiSceneSupport/EXPERIMENTS.md). Start
at the [canonical overview](../../../DatadogRUM/MULTI_SCENE_SUPPORT.md) for the
current support verdict and resume point.
