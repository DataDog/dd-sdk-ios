# Multi-scene integration and ownership guide

Review draft for F02. This branch remains experimental; the
[assessment](ASSESSMENT.md) defines its evidence limits.
[Stable API review](STABLE_API_REVIEW.md) owns the proposed public surface and
pending approval. This guide explains integration and attribution; it does not
change availability or declare release gates closed.

## Choose an integration

Existing single-scene applications keep their current setup and APIs.
Automatic UIKit and SwiftUI tracking remains the default. Each scene has one
current destination, while different scenes may have overlapping views within
the same RUM session. Sidebars, split panes and tab bars are structural regions,
not additional parallel destinations.

For exact SwiftUI navigation, connect an existing accepted-state source once per
independent router/container. Keep the application's navigation, destination,
sheet and full-screen-cover code. An accepted Home → Detail → Home sequence
creates three occurrences, including a fresh Home ID. Cancelled navigation creates
none. Integration work scales with containers, not screens.

| Application boundary | Integration | Exactness requirement |
| --- | --- | --- |
| Existing accepted-state publisher | `RUMNavigationHost(observing:destination:metadata:in:content:)` | Synchronously provide current accepted state, then accepted commits before immediate lifecycle work. Retain a stable source and distinguish repeated equal route occurrences. |
| Existing Observation router | `RUMNavigationHost(observingCurrentDestination:metadata:in:content:)` | Read one atomically updated accepted-state property, without side effects. Requires compiler>=6.4 as well as iOS27. Separate property writes are separate commits. |
| Third-party router/coordinator | One adapter exposing the accepted-state publisher above | Use trustworthy accepted callbacks and initial state. No per-screen RUM calls or retroactive conformance is required. |
| Opaque content/local state | Existing automatic tracking; optional content-only `RUMNavigationHost(in:content:)` | Best-effort discovery can be late and use structural names. A render-time value or eventual callback cannot establish exact immediate ownership. |
| Exceptional manual view | Scene-targeted start and stop below | Pair the same scene and key. Automatic tracking elsewhere continues. |

Automatic metadata derives type/enum-case names and supports sparse overrides.
Associated values and occurrence tokens are not serialized. A source must survive
SwiftUI value reconstruction. Configuring an empty source does not suppress
automatic tracking; semantic authority begins only after accepted materialization
and remains local to that container.

The first-release proposal keeps the low-level transitions/capability types and
native `RUMNavigationStack` convenience experimental. Their detailed adapter
contract remains in [NAVIGATION_API.md](NAVIGATION_API.md). Exact support does not
require adopting a Datadog navigation container.

## Experimental Swift call sites

These snippets use the current SPI deliberately. After F01 approval, F02 must
verify the approved imports, availability and compiling examples before publishing
this guide as supported documentation. The SDK deployment target remains iOS15;
the new target and semantic APIs are iOS27+ and iOS-only. Below that range keep
the existing inferred APIs; this is compatibility, not an exact multi-scene claim.

~~~swift
#if os(iOS)
import UIKit
@_spi(Experimental) import DatadogRUM

@MainActor
@available(iOS 27.0, *)
func beginCompose(on monitor: any RUMMonitorProtocol, in scene: UIWindowScene) {
    monitor.startView(key: "compose", name: "Compose", in: scene)
}

@MainActor
@available(iOS 27.0, *)
func finishCompose(on monitor: any RUMMonitorProtocol, in scene: UIWindowScene) {
    monitor.stopView(key: "compose", in: scene)
}

@MainActor
@available(iOS 27.0, *)
func recordCheckoutFailure(
    on monitor: any RUMMonitorProtocol,
    in scene: UIWindowScene
) {
    let target = RUMViewTarget.current(in: scene)
    monitor.addError(message: "Checkout failed", view: target)
    monitor.addViewAttribute(forKey: "checkout_retry_available", value: true, view: target)
}
#endif
~~~

The same manual key may be active independently in A and B. Do not pair a
scene-targeted start with a source-less stop. Distinct manual keys may nest;
stopping the top view reveals the latest committed underlying destination as a
fresh occurrence. Re-starting an already active scene/key is instrumentation
misuse; do not depend on additional lifecycle semantics for it.

A target captures the scene identifier on main and resolves that scene's live
current view when the command is processed. It neither freezes a view UUID nor
retains UIKit objects. If no live target resolves, independent inference and the
family's existing fallback still apply. A target is not a way to mutate an ended
view. Global monitor attributes remain process-wide.

Custom monitor conformers keep their existing requirements. Target extensions
forward once to their legacy method when the private built-in capability is
absent; they cannot promise exact scene targeting for a custom implementation.
NOP remains safe. Objective-C Release exposure, nullable factory behavior and
off-main misuse handling await the explicit [F01 decision](STABLE_API_REVIEW.md#objective-c-safety-before-release-exposure).
The Debug prototype is not a supported Release contract.

## Telemetry ownership

This table explains the fixed T01–T15 contracts. The
[register](release-gates.json) owns completion modes, status and decisive evidence.
No row implies simultaneous-device validation or adds a new telemetry family.

| Gate / family | Ownership and integration rule | Limit that callers must understand |
| --- | --- | --- |
| T01 / One-shot Actions | Explicit live view target; source-bearing automatic Actions use trustworthy event context. | Unresolved/source-less work retains independent inference and the process representative. An ordinary child task outside the handoff has no guaranteed originating scene. |
| T02 / Continuous Actions | Explicit start/stop targets select their own recipient. Stop attributes belong only to that recipient. | A target is not an Action handle. Preserve scene/pairing context; navigation and timeout retain existing lifecycle rules. |
| T03 / Resources | Explicit target or automatic/manual context is captured at start. Success, failure and metrics retain that view/session after navigation or session renewal. | Completion has no new target; re-targeting at finish would corrupt the captured owner. Use distinct active resource keys. |
| T04 / Current-view errors | Message, Error and completion forms accept an explicit live target. | Resource failures retain their Resource's captured owner instead. Callback completion does not prove an event was sampled or retained by a mapper. |
| T05 / View attributes/removal | Single/batch mutations accept an explicit live target. Global attributes still affect the process. | Ended views are not restored. Removing a view attribute can reveal the same-key global value; events already created keep their values. |
| T06 / Timing/loading | Explicit target selects the current view. Repeated timing names replace; loading time changes when absent or overwrite is true. | Timing/loading retain their separate expiration rules. Intermediate mapper revisions and final backend views are different evidence. |
| T07 / Flags/internal mutations | Customer flag evaluations accept an explicit target; Flags-bus and internal mutations carry captured call-site ownership where available. | FBC is a Flutter metric. Its absence from native iOS backend events is expected; native tests do not certify a Flutter integration. Internal metric/FBC APIs are not new customer APIs. |
| T08 / Traces | Manual, automatic and OpenTelemetry spans preserve captured start ownership through completion. | Source-less spans use process context. Do not infer ownership after causality is lost or rewrite requests across capture/header-injection boundaries. |
| T09 / Logs/mirrored errors | Capture context at emission and preserve it through deferred writing and mirrored-error delivery. | A log without trustworthy source context uses the process representative. Later queue context must not retarget it. |
| T10 / WebView | Capture native-container scene/date correlation; preserve it through bridge delivery and exact rebind/teardown. | Detached content has no invented scene owner. Internal scene metadata is removed; this does not promise scene-correct Session Replay. |
| T11 / Exported/fatal context | Export one process representative; retain an exact trustworthy internal snapshot for recovery. | A generic context read or crash has no independently proven originating window. Do not broadcast it or persist temporary scene metadata. |
| T12 / Long tasks, hangs, memory warnings | Emit once on the process representative. | These are process signals, not per-window measurements. The fallback may differ from the window a user associates with the symptom. |
| T13 / Vitals | Measure shared process/render-loop values and retain existing view association. | Concurrent views may observe shared values; they are not independent per-scene CPU/memory samples. |
| T14 / Profiling | One process profiler. Operation correlation uses exact start Vital IDs; profile labels carry the process context available to the profiler. | Profile-level view labels do not allocate CPU to scenes. A profile attachment's Operation ID joins to its RUM start; it does not carry a per-step view field. |
| T15 / Operations | Exact application-wide name/key identity; resolve each step's explicit or captured call-site owner independently, then last-proven/process fallback. | Scenes never namespace keys or permanently own later steps. Duplicate starts replace only the latest client instance and leave the earlier backend instance to its four-hour timeout. |

Use a unique Operation key for each concurrent instance. Complete it from the
scene performing that step rather than assuming its start scene owns every step.
The [Operation contract](OPERATIONS.md) contains the exact customer workflow and
failure/duplicate behavior. No API exposes internal RUM UUIDs or returns view
handles.

## Support boundaries and diagnostics

When ownership appears wrong, identify whether the event had a live explicit
target, a trustworthy captured owner, or only process context. Compare the exact
view ID and occurrence, not only the view name or event count. A repeated Home
name can correctly refer to a new occurrence. Check the source at the critical
lifecycle boundary; a settled final state does not prove earlier events were
attributed correctly.

Do not add per-scene sessions, temporary scene payload fields or independent
per-window process metrics. Window Execution Context serialization and true
multi-pane modeling are separate work. Session Replay requires crash-free
coexistence in this release; scene-correct recording is outside this contract.

The [assessment](ASSESSMENT.md) identifies the accepted evidence and remaining
physical/Duo, older-runtime and release checks. Simulator serial scenes, logical
peers and posted notifications cannot substitute for those checks. The
[runbook](TOOLING_RUNBOOK.md) owns validation procedures; this guide is not a run
cursor.

## Publication checklist within F02

1. Apply the recorded F01 decision to names, availability and Objective-C guidance.
2. Compile these examples and the approved semantic-host examples using normal
   imports in the F03 external-client cell, with the supported older fallback.
3. Review every T01–T15 row against its owning source and evidence, including FBC,
   captured Resource/Trace ownership and process-level signals.
4. Once the contract is ready to ship, update affected feature documentation
   through the repository's full feature-doc workflow, including cross-feature
   snippets and registries. Until then preserve the overview's separation from
   RUM_FEATURE.md. Do not bump verification metadata merely for this draft.
