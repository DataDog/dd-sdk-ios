# Multi-scene RUM: iOS Guild executive summary

Prepared September 21, 2026; status reviewed September 24, 2026.
Design feedback requested; public API approval and release qualification pending.

**My immediate goal is that RUM should not get worse when a developer rebuilds
their existing app with the iOS 27 SDK and runs it on iPhone Duo.** The longer-term
goal is reliable attribution when an app has several independently navigable
windows. These are separate delivery steps: existing customers should benefit
from reliability fixes without waiting for a new navigation integration.

The underlying problem is ownership. A process-wide “current view” cannot tell
which window started a request, received a tap or produced an error. SwiftUI adds
another ambiguity: constructing or showing a view does not always identify a
committed navigation visit. Both can produce plausible-looking events attached
to the wrong screen, even when the app never crashes.

**The work establishes a scene-aware ownership model and isolates fixes that
also benefit ordinary apps.** The experimental implementation keeps one current
destination per scene, with overlapping views sharing one application RUM
session. It tracks committed visits: Home → Detail → Home produces a fresh Home
occurrence on return. Manual exceptions and semantic navigation suppress their
own duplicate automatic tracking while other scenes continue independently.

The investigation also uncovered existing-customer defects in repeated network
interception, delayed Resource and Trace attribution, repeated-view attributes,
WebView correlation lifetime and display-link retention. Narrow fixes have been
prepared and locally qualified independently of the full multi-scene feature.
They still require the applicable delivery review and CI; local qualification
does not mean they have shipped.

**Ordinary RUM APIs keep their existing behavior and gain explicit scene
overloads where customers need them.** Automatic UIKit and SwiftUI tracking
remain the default. Existing source-less calls remain supported. The proposed
manual API makes the owning window explicit without exposing an internal RUM
view ID or returning a lifecycle handle:

~~~swift
// Proposed API, inside a MainActor-isolated UI integration on iOS 15+.
monitor.startView(key: "compose", name: "Compose", in: scene)
monitor.addAction(type: .tap, name: "Send", view: .current(in: scene))
monitor.stopView(key: "compose", in: scene)
~~~

On a qualified scene-aware path, two windows can use the same manual key without
stopping one another. Start and stop must use the same scene-taking overload and
key. Ending a manual exception reveals the latest underlying destination as a
fresh visit. The shared `RUMViewTarget.current(in:)` identifies the scene whose
live current view should receive a command; it does not freeze a particular
visit or retain UIKit objects.

| Kind of work | Ownership rule |
| --- | --- |
| Actions, current-view errors, timings, loading time, feature flags and view attributes | Use the explicit scene-current target where supported; preserve each family's existing lifecycle and fallback rules. |
| Resources and Traces | Preserve ownership captured at start through completion, failure and navigation. Resource completion does not acquire a new target. |
| Operations | Keep application-wide name/key identity. Each step resolves its own view, so an Operation can start in one window and finish in another. |
| Work without a trustworthy scene, and process signals | Use the documented process-level fallback. Shared CPU, memory and crash context do not become independent per-window measurements. |

**The updated proposal makes ordinary scene-taking APIs callable throughout
iOS 15+, with availability checks inside the SDK.** Customers should not need
`if #available(iOS 27.0, *)` around every call. Where enhanced scene behavior is
unavailable, the SDK invokes the equivalent existing RUM API exactly once,
preserving attributes, callbacks and pairing. It skips only the extra targeting;
the event must not disappear merely because the OS is older. Swift and
Objective-C follow the same proposed contract, with compatible custom/NOP
monitor forwarding.

Once customers adopt these overloads, qualified older-iPad improvements can
arrive through an SDK update without further instrumentation changes. Exact
scene behavior still needs validation on each enabled older-system path; legacy
fallback does not promise independent same-key windows. The ordinary iOS15
API and fallback are implemented provisionally at source `94842cc8ad7b`, with
optimized client checks on iOS17.5 and iOS27 recorded in
[EXP-225](Results/EXP-225-api-availability.json). Swift still requires SPI;
Objective-C is restricted to Debug or validation builds. Public approval,
normal Release exposure and final ownership checks remain pending. The complete
surface and safety contract are in the [Guild API review](STABLE_API_REVIEW_GUILD.md).

**The Navigation API offers optional semantic SwiftUI tracking at an existing
router or container boundary.** Customers keep their navigation containers,
routes, destination modifiers, sheets and covers. `RUMNavigationHost` observes
accepted navigation state and translates it into RUM occurrences:

~~~swift
// Proposed integration; the publisher and projection belong to the app.
// Inside a MainActor-isolated SwiftUI integration.
if #available(iOS 27.0, *) {
    RUMNavigationHost(
        observing: router.acceptedStates,
        destination: { $0.currentRUMDestination },
        metadata: .automatic
    ) {
        ExistingApplicationNavigation(router: router)
    }
} else {
    ExistingApplicationNavigation(router: router)
}
~~~

The intended integration cost is one boundary per independent router or flow,
without RUM calls in every screen or navigation method. Names derive from
destination types and enum cases, with optional centralized overrides; associated
values and occurrence tokens are not automatically serialized. A third-party
router can expose its accepted state through one reusable adapter.

The source must provide current accepted state synchronously and deliver commits
early enough to own immediate appearance or dismissal work. Rejected or
cancelled navigation creates no speculative visit; dismissing a presentation
reveals a fresh underlying occurrence. A render-time value or late callback
cannot guarantee this. The Observation initializer therefore reads one atomically
updated accepted-state property. A content-only host remains a best-effort option
when no exact source exists.

The semantic host remains **iOS 27+**; its Observation initializer also requires
compiler 6.4+. This requirement is separate from ordinary scene-taking APIs.
Low-level transition primitives and the Datadog navigation-container convenience
remain experimental. The [Guild navigation design](NAVIGATION_API_GUILD.md)
explains the integration choices, lifecycle contract and limitations.

**Validation checks event ownership at the critical boundary, alongside ordinary
compatibility and host safety.** Deterministic tests cover ordering, reentrancy,
repeated navigation, cancellation, teardown and captured owners. Native app
journeys compare automatic and manual tracking on regular devices and the Duo
simulator, complemented by physical iPhone/iPad evidence. Older-runtime checks
include iPadOS 17.5; an iOS 15 deployment build is kept distinct from execution
on iOS 15.

The acceptance harness binds clean installation, source/build identity, fresh run
identifiers, actual topology and input, local assertions and backend events.
It checks exact view owners and complete inventories. Negative controls reject
stale fixtures, consumed readiness signals and assertions that run too late.
One earlier journey appeared correct until assertions moved to immediate
lifecycle callbacks and exposed wrong ownership; that lesson now shapes the
validation contract.

The earlier SDK 27 Duo comparisons found no new foreground view/action coverage
loss in the exercised apps relative to the pre-scene SDK. Existing SwiftUI naming
and control-coverage limitations remain visible. Those results do not certify
every app or the newly composed release candidate: its native-input variability,
Duo/application checks and final acceptance remain open. Simulator results
support the exercised layout, lifecycle and ownership logic; physical Duo timing,
gestures and performance still need device confirmation. Required application
performance checks concern frame rate, hitches, CPU, memory and retained state
for the changes actually included. Session Replay is scoped to host safety and
non-disruption to other SDK features.

**The release plan separates immediate customer protection from full feature
adoption.**

| Release step | Customer outcome | Exit criteria and timing |
| --- | --- | --- |
| Independent reliability fixes | Existing apps gain narrow correctness and lifetime repairs without new integration. | Deliver each qualified fix independently after its applicable CI, review and final source checks. The [reliability delivery plan](S1_DELIVERY_PLAN.md) owns each fix's PR and validation status. |
| Single-scene iPhone Duo readiness | An app rebuilt with SDK 27 is no worse without major application changes. No new scene or Navigation API adoption is required. | Target October 16, 2026. The selected composition has compatibility qualification; current-candidate Duo, app/backend and final release checks remain. Disclose unavailable physical Duo evidence and confirm it when hardware is available. |
| Full multi-scene support | Independent scene ownership, reviewed manual/telemetry APIs and optional semantic SwiftUI navigation. | Release after API review, implementation, ownership/lifecycle and client compatibility checks, application performance qualification and physical Duo acceptance. No committed date yet. |

Progress is measured by finite release requirements, each with an owner,
dependency, decisive test and environment. Evidence applies to its recorded
source and environment; extracting or recomposing a candidate requires checking
what changed before reusing previous results. The [release checklist](PLAN.md)
and [current assessment](ASSESSMENT.md) retain the detailed status behind this
meeting snapshot.

**I would like early Guild feedback on three decisions:**

- Is explicit scene-current targeting, including the distinction from captured
  start ownership and older-system fallback, clear and practical?
- Can our customers' routers provide accepted navigation state at the required
  boundary with one integration, without widespread instrumentation changes?
- Are the proposed Swift/Objective-C surface and staged release boundaries the
  right balance of adoption cost, compatibility and confidence?
