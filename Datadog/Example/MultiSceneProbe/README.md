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

The catalog currently preserves these experiment families:

| Scenario | Evidence preserved | Execution level |
| --- | --- | --- |
| `interactive.manual` | Interactive automatic-tracking control | Existing UI controls |
| `swiftui.automatic.single-window` | `EXP-027` | Existing deterministic automation |
| `swiftui.automatic.two-window` | `EXP-028` | Existing deterministic automation |
| `swiftui.stack.occurrence-push` | `EXP-090` setup | Existing deterministic automation |
| `swiftui.stack.return` | `EXP-098`, `EXP-099` | Observable driver pending |
| `swiftui.stack.abort` | `EXP-091` | Existing deterministic automation |
| `swiftui.stack.same-type-replacement` | `EXP-090` | Existing deterministic automation |
| `swiftui.stack.different-type-replacement` | `EXP-054` | Existing deterministic automation; keyed rerun pending |
| `swiftui.stack.manual-sheet-return` | `EXP-040` | Observable driver pending |
| `swiftui.stack.native-pop-cancel`, `swiftui.stack.native-pop-finish` | `EXP-100` | Prepared; hardware or human gesture required |
| `swiftui.split.automatic-baseline` | `EXP-069` | Existing deterministic automation |
| `swiftui.split.same-type-selection` | `EXP-102` | Existing deterministic automation |
| `swiftui.split.same-type-selection-two-scenes` | `EXP-103` | Existing deterministic automation; simultaneous topology remains unproven |
| `swiftui.split.retained-return` | `EXP-105` | Existing deterministic automation |
| `swiftui.split.empty-selection` | `EXP-087` | Existing deterministic control |
| `uikit.split.replacement`, `uikit.split.subclass` | `EXP-080`, `EXP-072` | Existing deterministic automation |
| `uikit.split.pop-automatic` | `EXP-079` | Existing deterministic automation |
| `uikit.split.pop-cancel`, `uikit.split.pop-finish` | `EXP-083`, `EXP-084` | Existing deterministic transition control |
| `uikit.split.native-pop-control`, `uikit.split.native-pop-cancel`, `uikit.split.native-pop-finish` | `EXP-081`, `EXP-082` | Prepared; cancellation needs hardware or human input |
| `uikit.split.concurrent-scenes` | `EXP-086` | Existing automation; simultaneous topology remains unproven |
| `windows.parallel-navigation` | `EXP-033`, `EXP-059`, `EXP-103` | Existing automation; simultaneous topology remains unproven |
| `windows.close-with-resource` | `EXP-041` | Existing close control; visible-peer proof needs hardware |
| `actions.exact-source-handoff` | `EXP-089` | Existing filtered control; discriminator needs simultaneous topology |
| `swiftui.reader.synthetic-reconnect`, `swiftui.reader.synthetic-reconnect-scene-b` | `EXP-066` | Existing synthetic control |
| `windows.restoration` | `EXP-042` | Prepared; concurrent restoration needs hardware or human setup |
| `diagnostic.swiftui.offscreen-tab` | `EXP-036` | Existing diagnostic control |
| `diagnostic.swiftui.navigation-path.same-type-replacement`, `diagnostic.swiftui.navigation-path.split-selection` | `EXP-057`, `EXP-068` | Superseded diagnostic controls retained for reproduction |
| `regression.single-scene` | `EXP-026`, `EXP-032` | Existing deterministic automation |

The scenario manifest already models ordered steps, signal waits, completion
conditions, required capabilities, and the expected semantic timeline. The
current app still executes its existing automation controls while the observable
step driver and local semantic oracle are added in subsequent harness phases.
Do not treat a modeled timeline as a local PASS until that oracle is present.

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
Detail selection across Detail 1 -> Detail 2 replacement. In this mode
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
action/resource marker. The required RUM occurrence order is
`Primary → Secondary₁ → Secondary₂`, with no restarted Primary between the two
secondaries. Use `uikit-split-subclass` only as the follow-up control that swaps
the stock container for an application subclass; this reveals whether the
container itself becomes an extra automatically tracked RUM view.
Set `DD_MULTI_SCENE_SWIFTUI_LAYOUT=uikit-split-navigation` for the stock split
navigation control. It keeps one secondary `UINavigationController`, installs
Secondary 1 as its stable root, pushes a fresh same-class Secondary 2, and pops
back to the same Secondary 1 controller. The required occurrence order is
`Primary → Secondary₁ → Secondary₂ → Secondary₁`, with a fresh UUID for the
returned Secondary 1 and no Primary occurrence during either push or pop.
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
`probe.screen`, and `probe.phase`. Event mappers print the RUM session, view,
action, and resource IDs selected by the SDK. Query ingested events with:

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
