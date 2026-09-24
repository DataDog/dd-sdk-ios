# Multi-scene RUM stable API review

Status: PROPOSED — F01 reviewer decision pending. No declaration is promoted and
no public API baseline is changed by this document.

Original proposal source: 2baa06da0060bcc4ae3b54fe2f4cfc64be5b4cce. Local
implementation: 94842cc8ad7b104c1394c236b98b95b6c24a0956, qualified provisionally
in [EXP-225](Results/EXP-225-api-availability.json). The
[gate register](release-gates.json) owns F01 status; the
[approved contract](../MULTI_SCENE_SUPPORT.md) owns product behavior.
[Navigation](NAVIGATION_API.md) and [Operations](OPERATIONS.md) own their semantic
contracts; [navigation history](Experiments/NAVIGATION_API_HISTORY.md) preserves
the earlier designs and observations. This document is the canonical declaration
inventory and approval record. Guild presentations link here rather than keeping
separate inventories. The proposal remains subject to review.

Availability amendment, 2026-09-21: the user requests ordinary scene-taking APIs
across the SDK's iOS15+ range, with platform checks inside the SDK. The inspected
local implementation now declares those ordinary APIs at iOS15 and qualifies
internal fallback and provisional clients. Public exposure and final compatibility
remain pending. The semantic SwiftUI host retains its separate iOS27 requirement.

## Decision requested

Approve or amend these eight decisions as one bounded RFC direction. Record the
reviewer, date and approval reference before public promotion. Local implementation
and provisional qualification are authorized before that review. F01 closes when the
reviewed contract is implemented and verified, with an attributable disposition.
S3 F02 documentation, F03 final platform matrix and F06 freeze retain their own gates.
S1/S2 preserve existing APIs and do not wait for unrelated scene declarations. The
earlier assessment assumption of accepted APIs is not an attributable F01 decision.

| Decision | Proposed first-release contract | Evidence and decisive follow-up |
| --- | --- | --- |
| 1. Availability | Ordinary scene-taking overloads, RUMViewTarget, its experimental alias and Objective-C companions are callable on iOS15+, without customer iOS27 guards. The SDK selects qualified scene behavior or existing family behavior internally. Semantic host/destination/metadata APIs remain iOS27+; Observation also requires compiler>=6.4. All additions remain iOS-only. | Require unguarded Swift/Objective-C scene clients targeting iOS15, legacy parity on an available older runtime, and per-family evidence before enabling exact older-iPad behavior. Semantic clients retain their guards. API availability alone makes no wider multi-scene claim. |
| 2. Target and names | Promote RUMViewTarget.current(in:) and the 21 implemented Swift overloads below. Keep required view argument. RUMOperationViewTarget remains an experimental migration alias. Add no inferred/manual-key/controller factories. | T01–T07/T15 ownership evidence. Exact-key/controller factories stay outside this release rather than adding gates. |
| 3. Conformers | Extension-only overloads with existing private capabilities. Monitor honors targets; custom/NOP conformers invoke their existing inferred method once. No protocol witness or changed shared-monitor return type. | Existing forwarding/custom/NOP controls; F03 requires an external conformer using normal imports. Document the custom-conformer targeting limit. |
| 4. Objective-C | Promote the 20 targeted selectors and DDRUMViewTarget.currentInScene:, preserving names/conversions. Swift Error completion overload stays Swift-only. | EXP-225 qualifies provisional optimized main/off-main clients under DD_SCENE_API_VALIDATION. Approve the safety rule below and verify the normal Release header/client before removing the exposure guard. |
| 5. Semantic host | Promote RUMNavigationHost content-only, accepted-state Publisher and observingCurrentDestination initializers, plus RUMNavigationDestination and RUMNavigationMetadata. Keep standard navigation/presentation and customer-owned state. | R06 and EXP-147–154/168–174. No exactness claim for opaque local @State, render-time values or late callbacks. |
| 6. Adapter boundary | Keep RUMNavigationTransitions, RUMNavigationTransitionProviding, transitions host initializer, RUMNavigationStack and its presentation types experimental. Stable third-party adapters use the accepted-state Publisher host. | Retains the exercised container-independent path without freezing low-level prepare/commit/cancel or mirrored native-container APIs. No new primitive/dependency. |
| 7. Metadata/authority | Automatic type/enum-case metadata, sparse overrides, no serialized associated values/occurrence tokens/scene IDs. Authority starts after accepted materialization, stays container-local and releases at final teardown. | R02–R06 and D03/D07–D10. Document stable source, synchronous initial state and one atomic Observation property. |
| 8. Migration/ownership | Existing apps keep APIs/defaults. Exact integration is optional per router/container. Manual pairing uses scene/key; each Operation step resolves context; Resources capture at start. | [Assessment](ASSESSMENT.md) and T01–T15. No public RUM UUID, returned view handle, wire change, scene session, per-window CPU or route-proportional instrumentation. |

Approval record: **pending**.

**Ordinary API availability and runtime behavior.** `UIWindowScene` and its
session identifier predate the SDK's iOS15 minimum. Their use does not require
an iOS27 public declaration. The first-release proposal therefore lowers the
availability of all 21 Swift overloads below, `RUMViewTarget.current(in:)`, the
experimental `RUMOperationViewTarget` alias, all 20 Objective-C monitor selectors
and `DDRUMViewTarget.currentInScene:` to iOS15. Required `in:`/`view:` arguments,
names, defaults and the extension-only compatibility strategy stay unchanged.

Before mutating tracking state, the SDK chooses a route using the operating
system, configuration and the qualified capability for that telemetry family.
On a supported scene-aware route, it honors the scene target. Otherwise it
invokes the equivalent existing RUM method exactly once, preserving attributes,
completion behavior and that family's pairing rules. Only the extra targeting
behavior is absent: a valid call on an older OS must not silently drop its view
or event, duplicate it, or require a second customer fallback call. Custom/NOP
conformers retain the same exactly-once forwarding contract.

Customers use the same overloads for a matching start/stop pair on every OS.
The SDK must keep the pair on a coherent route. Legacy fallback preserves legacy
inferred/process attribution; it does not promise independent same-key A/B
manual views or exact scene ownership. Resource completion and metrics keep the
owner captured at start, continuous Actions keep their pairing contract, and
Operations keep application-wide identity with independent per-step resolution.
Unsupported scene behavior must not replace these existing family contracts.

The target factory captures only a scene identifier on the main actor and
retains no UIKit object. Availability and interpretation belong to the receiving
monitor, so the same customer call can gain qualified older-iPad behavior after
an SDK update without another instrumentation edit. Enable that behavior only
for families whose ownership and coexistence tests pass on the older system;
do not equate removal of an annotation with a validated backport.

| Acceptance requirement for the availability amendment | Decisive result | Required environment |
| --- | --- | --- |
| Ordinary call-site compatibility | All 21 Swift overloads, target/alias and all Objective-C companions compile without customer iOS27 guards; normal imports work after approved exposure. | Swift and Objective-C Release clients targeting iOS15; supported compilers/platform SDKs. |
| Legacy fallback parity | Invoke the legacy path once and match its event stream, attributes, stop attributes and completion behavior; automatic on/off and custom/NOP paths retain their behavior. | Focused tests and the available iPadOS17.5 runtime. |
| Existing exact scene behavior | Same-scene/key pairing, reverse-order A/B stops, peer continuity and targeted telemetry owners remain correct. | Existing iOS27 scene-capable test environments; current topology gates remain. |
| Before enabling optional older-iPad scene capability | Exercise manual A/B ownership, current-view events and delayed Resource completion after navigation. Enable only each family proven by its owner oracle; others keep fallback. | iPadOS17.5 multi-window runtime, with backend ownership checks where required by the existing family gate. |
| Safety and lifecycle | No duplicate/drop, reentrancy regression, retained UIKit object or unnecessary retained scene state on fallback; start-owned Resources never retarget at completion. | Focused forwarding/lifetime tests and existing compatibility/performance checks. |
| Semantic boundary unchanged | Host/destination/metadata calls stay guarded for iOS27; the Observation initializer keeps its compiler>=6.4 condition. | Supported Swift client compilation. |

An iOS15 deployment-target build establishes compile/link compatibility, not an
iOS15 runtime result. Use the oldest available runtime for execution and state
its version. This amendment fits the existing API/client/compatibility
deliverables; it does not create an open-ended older-system experiment campaign.

## Objective-C safety before Release exposure

At source `94842cc8ad7b`, the provisional Objective-C entry shims check the
calling thread before entering actor-isolated Swift code or accessing UIKit.
EXP-225 qualifies optimized main/off-main clients on iOS17.5 and iOS27 under
`DD_SCENE_API_VALIDATION`: the off-main factory returns nil and targeted calls
return safely. The declarations remain hidden in ordinary Release builds.
F01 must still approve this contract and verify the promoted public header/client.

Proposed behavior: Objective-C entry shims check the calling thread before crossing
actor-isolated Swift entry or dereferencing UIKit. The factory returns nil off-main
with a nullable Objective-C result. Invalid off-main targeted calls are ignored
safely; they neither schedule a later UIKit read, retain the scene, synchronously
dispatch to main, nor silently retarget a different view. Main-thread behavior
keeps the exercised contract. Swift factories/overloads retain @MainActor.
The provisional nullable factory is implemented locally; promoting that shape
requires explicit reviewer approval.

Before promotion, an Objective-C Release fixture must invoke factory and
manual/telemetry companions on and off main: no SDK trap/deadlock, no UIKit
access/retention on invalid paths, and no foreign telemetry. Verify exactly-once
custom/NOP fallback on valid calls. If reviewers choose another rule, freeze its
decisive test before implementation.

## Swift target surface

The 21 experimental overloads were checked in
`DatadogRUM/Sources/RUMMonitorProtocol+Convenience.swift` at source
`94842cc8ad7b104c1394c236b98b95b6c24a0956`, as recorded in
[EXP-225](Results/EXP-225-api-availability.json). The proposed public surface
preserves those signatures/defaults and iOS15 availability. These overloads remain
@MainActor and extension-only on RUMMonitorProtocol; the implementation still
requires an experimental import. RUMViewTarget captures only the scene
identifier on main; a qualified scene-aware route resolves its live current view.
It is not a snapshot of a view UUID.

~~~swift
@available(iOS 15.0, *)
public struct RUMViewTarget {
    @MainActor
    public static func current(in scene: UIWindowScene) -> Self
}
~~~

~~~swift
@available(iOS 15.0, *)
@MainActor
public extension RUMMonitorProtocol {
    func addFeatureFlagEvaluation(name: String, value: Encodable, view: RUMViewTarget)

    func addTiming(name: String, view: RUMViewTarget)

    func addViewLoadingTime(overwrite: Bool, view: RUMViewTarget)

    func addViewAttribute(forKey key: AttributeKey, value: AttributeValue, view: RUMViewTarget)

    func addViewAttributes(_ attributes: [AttributeKey: AttributeValue], view: RUMViewTarget)

    func removeViewAttribute(forKey key: AttributeKey, view: RUMViewTarget)

    func removeViewAttributes(forKeys keys: [AttributeKey], view: RUMViewTarget)

    func startView(
        key: String,
        name: String? = nil,
        in scene: UIWindowScene,
        attributes: [AttributeKey: AttributeValue] = [:]
    )

    func stopView(
        key: String,
        in scene: UIWindowScene,
        attributes: [AttributeKey: AttributeValue] = [:]
    )

    func addError(
        message: String,
        type: String? = nil,
        stack: String? = nil,
        source: RUMErrorSource = .custom,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:],
        file: StaticString? = #fileID,
        line: UInt? = #line
    )

    func addError(
        error: Error,
        source: RUMErrorSource = .custom,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    )

    func addError(
        error: Error,
        source: RUMErrorSource = .custom,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:],
        completionHandler: @escaping CompletionHandler
    )

    func startResource(
        resourceKey: String,
        request: URLRequest,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    )

    func startResource(
        resourceKey: String,
        url: URL,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    )

    func startResource(
        resourceKey: String,
        httpMethod: RUMMethod,
        urlString: String,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    )

    func addAction(
        type: RUMActionType,
        name: String,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    )

    func startAction(
        type: RUMActionType,
        name: String,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    )

    func stopAction(
        type: RUMActionType,
        name: String? = nil,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    )

    func startOperation(
        name: String,
        operationKey: String? = nil,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:],
        options: OperationOptions? = nil
    )

    func succeedOperation(
        name: String,
        operationKey: String? = nil,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    )

    func failOperation(
        name: String,
        operationKey: String? = nil,
        reason: RUMFeatureOperationFailureReason,
        view: RUMViewTarget,
        attributes: [AttributeKey: AttributeValue] = [:]
    )

}
~~~

On a qualified scene-aware route, unresolved targets retain independent
inference and family-specific fallback. A route without the qualified capability
uses the equivalent legacy API once before scene-specific state is mutated.
Only Resource starts accept targets; completion/metrics retain their captured
owner. Continuous Actions retain their own pairing rules. Operations use exact
application-wide (name, optional key) identity and resolve every step separately.
Global monitor attributes remain process-wide.

## Objective-C selector inventory

Observed Debug inventory in [RUM+objc.swift](../Sources/RUM+objc.swift). Preserve
these selectors with the nullable factory/safe entry behavior proposed above.
No Objective-C equivalent of Swift's Error completion overload is promised.

~~~text
currentInScene:
addViewAttributeForKey:value:view:
addViewAttributes:view:
removeViewAttributeForKey:view:
removeViewAttributesForKeys:view:
addTimingWithName:view:
addViewLoadingTimeWithOverwrite:view:
startViewWithKey:name:inScene:attributes:
stopViewWithKey:inScene:attributes:
addErrorWithMessage:stack:source:view:attributes:
addErrorWithError:source:view:attributes:
startResourceWithResourceKey:request:view:attributes:
startResourceWithResourceKey:url:view:attributes:
startResourceWithResourceKey:httpMethod:urlString:view:attributes:
addActionWithType:name:view:attributes:
startActionWithType:name:view:attributes:
stopActionWithType:name:view:attributes:
addFeatureFlagEvaluationWithName:value:view:
startOperationWithName:operationKey:view:attributes:options:
succeedOperationWithName:operationKey:view:attributes:
failOperationWithName:operationKey:reason:view:attributes:
~~~

## Stable semantic host proposal

Preserve these implemented initializer shapes and core defaults. The semantic
host, destination and metadata types remain iOS27+; this amendment does not
backport their implementation. The host's `in:` parameter selects the Datadog
SDK core instance, not a UIWindowScene.

~~~swift
RUMNavigationHost(in:content:)
RUMNavigationHost(observing:destination:metadata:in:content:)
RUMNavigationHost(observingCurrentDestination:metadata:in:content:)
~~~

Publisher requires Output == State and Failure == Never with a @MainActor
projection. Observation also uses a @MainActor projection and compiler>=6.4.
Content-only supplies automatic compatibility and can consume the existing
experimental capability without exposing it in the stable signature; it does
not promise exact opaque-container reconstruction.

Preserve these destination/metadata factory shapes:

~~~swift
RUMNavigationDestination.root(_:attributes:)
RUMNavigationDestination.route(_:attributes:)
RUMNavigationDestination.route(_:occurrence:attributes:)
RUMNavigationDestination.presentation(_:attributes:)
RUMNavigationMetadata.init()
RUMNavigationMetadata.automatic
RUMNavigationMetadata.automatic(in:)
RUMNavigationMetadata.overriding(_:name:path:)
~~~

Destination/occurrence values are Hashable; attributes default empty and override
path defaults nil. Metadata never encodes associated values. Occurrence tokens
are in-memory application identities, never RUM UUIDs or payload attributes.

Publisher adapters must synchronously seed accepted current state, emit commits
before immediate lifecycle work, distinguish equal occurrences and retain one
subscription per container. Observation must read one atomically updated
accepted-state property without side effects; separate writes are separate
commits. An empty configured source does not seize authority or switch sources.

## Migration and compatibility checks

| Existing integration | Migration | Required proof |
| --- | --- | --- |
| Ordinary single-scene automatic/manual | No code change. | C01–C03 behavior and older-system guards. |
| New ordinary scene-taking calls | One integration across iOS15+, with no caller iOS27 branch. | Unguarded client compilation and exactly-once legacy fallback; separate owner qualification before enabling optional older-iPad scene behavior. |
| Native multi-scene UIKit | Keep automatic tracking; optionally target exceptional manual views/telemetry. | Scene/key pairing, fresh occurrences, peer continuity; physical H gates remain. |
| Observable router | One host/projection at the boundary; preserve navigation and presentations. | No screen/navigation-method edits or extra RUM code per new route absent optional naming. |
| Third-party callbacks | One accepted-state Publisher adapter. | Synchronous accepted callbacks/initial state and stable subscription; no retroactive conformance. |
| Opaque SwiftUI/local @State | Automatic tracking and sparse manual exceptions. | Document timing/structural-name limits; no exact render-time claim. |
| Custom monitor/NOP | Existing conformance unchanged. | One legacy fallback, no recursion/witness or exact custom scene claim. |
| Experimental import | Migrate only approved calls; keep SPI import for retained experimental types. | Preserve internal probes and alias during review. |

After approval, changes are limited to declarations/bridges, necessary tests,
API baselines through existing tooling, and support/feature documentation.
Deferred extraction, new target forms, dependencies and wire changes are excluded.

## Required dispositions

| Deliverable | Owner | Dependency | Decisive result | Environment |
| --- | --- | --- | --- | --- |
| Decide 1–8 with amendments | RUM API reviewers | T03–T07, R06 closed | Attributable RFC approval | API review |
| Align and promote reviewed declarations/safety | SDK implementer | Recorded approval; provisional EXP-225 implementation | Exact approved declarations and positive/negative forwarding/off-main controls with the normal public surface | Xcode, simulator, Objective-C Release client |
| External conformer and availability clients | SDK implementer | Approved exposure | Unguarded ordinary scene clients and guarded semantic clients compile; old conformers/defaults and fallback work | Swift/Objective-C Release clients targeting iOS15, supported compilers and available older runtime |
| API baselines and migration guide | SDK implementer | Reviewed declarations | Reviewed generated diff, compiling examples | Existing API tooling |
| Release acceptance | Gate owners | Recorded gate dependencies | F02/F03/F04/F05/F06 close on their own evidence | Review, CI, required hardware |

This decomposes F01's existing deliverable; it adds no gates or experiment quota.
Physical/Duo evidence remains mandatory regardless of API approval.

The repository [AGENTS.md](../../AGENTS.md) requires: “Do NOT introduce new public
API without RFC review.” The [development guide](../../docs/DEVELOPMENT.md#rfc-process-for-major-changes)
also requires internal RFC approval and cross-platform alignment for significant
public API changes. This is why a reviewer decision is required for promotion;
documentation preparation and existing experimental validation can continue.
