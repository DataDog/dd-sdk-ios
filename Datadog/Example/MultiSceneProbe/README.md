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

Open `RUMNativeMultiSceneProbe.xcodeproj`, select an iPadOS 27 simulator, and set
these run environment variables:

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
With `navigation-path` tracking and route identity disabled, the required RUM
occurrences are `Detail₁ → Detail₂ → Placeholder`, each with a distinct UUID and
without an intervening Sidebar or Home. Enabling
`DD_MULTI_SCENE_FORCE_ROUTE_IDENTITY=1` applies the same probe-only `.id(route)`
control to these split destinations. The sequence is skipped in compact width.
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
