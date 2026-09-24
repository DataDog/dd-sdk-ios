# Multi-scene integration and ownership guide

Review draft for S3:F02. S1/S2 publish only their actual candidate changes and
existing-API limitations; this guide does not require those releases to adopt new
scene APIs. This branch remains experimental; the
[assessment](ASSESSMENT.md) defines its evidence limits.
[Stable API review](STABLE_API_REVIEW.md) owns the proposed public surface and
pending approval. This guide explains integration and attribution; it does not
change availability or declare release gates closed.

## Choose an integration

Existing single-scene applications keep their current setup and APIs.
Legacy UIApplication lifecycle remains compatible for apps built with an earlier
SDK: [C03's comparison](Results/EXP-189-legacy-build-sdk.json) checks genuine26.5-SDK
hosts on27.0/26.5. When building with SDK27, adopt the scene lifecycle required by
[Apple](https://developer.apple.com/documentation/uikit/transitioning-to-the-uikit-scene-based-life-cycle).
The SDK cannot make a platform-rejected legacy host launch. Scene-lifecycle
adoption does not require enabling multiple windows.

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

The semantic host and destination/metadata types remain iOS27+; the Observation
form also needs compiler>=6.4. This is separate from the ordinary scene-taking
monitor APIs proposed below across iOS15+.

The first-release proposal keeps the low-level transitions/capability types and
native `RUMNavigationStack` convenience experimental. Their detailed adapter
contract remains in [NAVIGATION_API.md](NAVIGATION_API.md). Exact support does not
require adopting a Datadog navigation container.

## Proposed Swift call sites

These snippets show the September21 availability amendment: ordinary
scene-taking calls and RUMViewTarget are callable throughout the SDK's iOS15+
range, without a customer iOS27 branch. They show the intended normal import
after approved exposure. The local prototype still requires SPI imports, but
ordinary declarations now support iOS15. [EXP-225](Results/EXP-225-api-availability.json)
records provisional compiled/runtime clients and their limits. F01 public
promotion and F02 verification of approved imports, availability and examples
remain required before publishing this guide as supported documentation.

The SDK checks OS, configuration and the qualified family capability internally.
Where enhanced scene behavior is unavailable, it calls the equivalent existing
API exactly once with the same attributes and completion behavior. It skips
only the extra targeting, not the telemetry itself. Legacy inferred/process
ownership remains the fallback; API availability does not establish exact
multi-scene behavior on every older system. Qualified older-iPad improvements
can then ship in an SDK update without another customer instrumentation change.

~~~swift
#if os(iOS)
import UIKit
import DatadogRUM

@MainActor
func beginCompose(on monitor: any RUMMonitorProtocol, in scene: UIWindowScene) {
    monitor.startView(key: "compose", name: "Compose", in: scene)
}

@MainActor
func finishCompose(on monitor: any RUMMonitorProtocol, in scene: UIWindowScene) {
    monitor.stopView(key: "compose", in: scene)
}

@MainActor
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

Use the same scene-taking overloads for start and stop on every OS; the SDK must
keep their routing coherent. Legacy fallback does not promise independent
same-key A/B views. On the qualified scene-aware path, the same manual key may
be active independently in A and B. Do not pair a scene-targeted start with a
source-less stop. Distinct manual keys may nest;
stopping the top view reveals the latest committed underlying destination as a
fresh occurrence. Re-starting an already active scene/key is instrumentation
misuse; do not depend on additional lifecycle semantics for it.

A target captures the scene identifier on main. On a qualified scene-aware
route, it resolves that scene's live current view when the command is processed.
It neither freezes a view UUID nor retains UIKit objects. If no live target
resolves, independent inference and the
family's existing fallback still apply. A target is not a way to mutate an ended
view. Global monitor attributes remain process-wide.

Custom monitor conformers keep their existing requirements. Target extensions
forward once to their legacy method when the private built-in capability is
absent; they cannot promise exact scene targeting for a custom implementation.
NOP remains safe. The proposed Objective-C companions share iOS15+ callability
and the same internal fallback. EXP-225 provisionally qualifies the nullable
factory and off-main guards in optimized clients under `DD_SCENE_API_VALIDATION`.
Approval of that safety contract and normal Objective-C Release exposure still
await the explicit
[F01 decision](STABLE_API_REVIEW.md#objective-c-safety-before-release-exposure).
The Debug/validation-only declarations are not a supported Release contract.

## Telemetry ownership

This table explains the fixed T01–T15 contracts. The
[register](release-gates.json) owns completion modes, status and decisive evidence.
No row implies simultaneous-device validation or adds a new telemetry family.
Explicit scene behavior in this table applies where the family is qualified;
otherwise the ordinary overload preserves its existing family's legacy
semantics. In particular, fallback does not retarget a Resource at completion or
turn an Operation's identity into scene-local state.

| Gate / family | Ownership and integration rule | Limit that callers must understand |
| --- | --- | --- |
| T01 / One-shot Actions | Explicit live view target; source-bearing automatic Actions use trustworthy event context. | Unresolved/source-less work retains independent inference and the process representative. An ordinary child task outside the handoff has no guaranteed originating scene. |
| T02 / Continuous Actions | Explicit start/stop targets select their own recipient. Stop attributes belong only to that recipient. | A target is not an Action handle. Preserve scene/pairing context; navigation and timeout retain existing lifecycle rules. |
| T03 / Resources | Explicit target or automatic/manual context is captured at start. Success, failure and metrics retain that view/session after navigation or session renewal. | Completion has no new target; re-targeting at finish would corrupt the captured owner. Use distinct active resource keys. |
| T04 / Current-view errors | Message, Error and completion forms accept an explicit live target. | Resource failures retain their Resource's captured owner instead. Callback completion does not prove an event was sampled or retained by a mapper. |
| T05 / View attributes/removal | Single/batch mutations accept an explicit live target. Global attributes still affect the process. | Ended views are not restored. Removing a view attribute can reveal the same-key global value; events already created keep their values. |
| T06 / Timing/loading | Explicit target selects the current view. Repeated timing names replace; loading time changes when absent or overwrite is true. | Timing/loading retain their separate expiration rules. Intermediate mapper revisions and final backend views are different evidence. |
| T07 / Flags/internal mutations | Customer flag evaluations accept an explicit target; Flags-bus and internal mutations carry captured call-site ownership where available. | FBC is a Flutter metric. Its absence from native iOS backend events is expected; native tests do not certify a Flutter integration. Internal metric/FBC APIs are not new customer APIs; delayed mutations follow the same-scene stale-view rules below. |
| T08 / Traces | Manual, automatic and OpenTelemetry spans preserve captured start ownership through completion. | Source-less spans capture process context at start; an authoritative captured absence stays absent. Do not infer ownership after causality is lost or rewrite requests across capture/header-injection boundaries. |
| T09 / Logs/mirrored errors | Freeze log context at emission; carry captured view/action intent into mirrored-error routing. | Source-less logs use process context. A delayed mirror follows current-view stale-owner rules; it can move to the next view in its known scene or be dropped, while the log keeps its snapshot. |
| T10 / WebView | Capture native-container scene/date correlation; preserve it through bridge delivery and exact rebind/teardown. | Native container correlation requires matching replay-enabled view history. Ambiguous source-less history stays uncorrelated; single-scene legacy fallback remains. Private scene metadata is removed. Replay scene correctness remains separate. |
| T11 / Exported/fatal context | Export one process representative; retain an exact trustworthy internal snapshot for recovery. | A generic context read or crash has no independently proven originating window. Do not broadcast it or persist temporary scene metadata. |
| T12 / Native long tasks, hangs, memory warnings | Native detectors emit once on the process representative; fatal recovery uses T11. | These are process signals, not per-window measurements. Cross-platform internal long-task injection can carry call-site context; it does not make native detection scene-specific. |
| T13 / Vitals | Aggregate shared system CPU ticks, process memory and render-loop values over each view's lifetime. | Concurrent views may observe shared values; they are not independent per-scene CPU/memory samples. |
| T14 / Profiling | One process profiler. Operation correlation uses exact start Vital IDs; profile-level attributes come from received RUM correlation messages. | Profile-level view labels do not allocate CPU to scenes. A profile attachment's Operation ID joins to its RUM start; it does not carry a per-step view field. |
| T15 / Operations | Exact application-wide name/key identity; resolve each step's explicit or captured call-site owner independently, then last-proven/process fallback. | Scenes never namespace keys or permanently own later steps. Local tracking is bounded and session-local. Duplicate starts replace only the latest client instance and leave the earlier backend instance to its documented four-hour timeout. |

Delayed current-view commands do not restore ended occurrences. When retained
history identifies an old view's scene, routing may select that scene's current
view; missing scene-owned history cannot borrow a peer. Existing scene-less
legacy fallback remains. This differs from a Resource or span whose start owner
is retained, and from an unavailable explicit target that leaves independent
inference intact.

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
2. Compile ordinary scene-call examples without customer iOS27 guards in Swift
   and Objective-C Release clients targeting iOS15. Keep the approved semantic
   host's OS/compiler guards. Verify legacy parity on the available older
   runtime and exact older-iPad behavior only for families explicitly qualified.
3. The previous T01–T15 ownership review covers source `04201edc7`;
   [source and evidence audit](Results/F02-guide-ownership-audit.json) records its
   exact files, limits and accepted predecessors. The provisional availability
   amendment at `94842cc8ad7b` has a separate
   [source review](Results/S3-F02-provisional-documentation-review.json).
   Recheck affected ownership rows against the approved release source before
   publication; neither record is the final feature-document audit.
4. Once the contract is ready to ship, update affected feature documentation
   through the repository's full feature-doc workflow, including cross-feature
   snippets and registries. Until then preserve the overview's separation from
   RUM_FEATURE.md. Do not bump verification metadata merely for this draft.
