# Multi-scene RUM stable API review

Status: PROPOSED — F01 reviewer decision pending. No declaration is promoted and
no public API baseline is changed by this document.

Review source: 2baa06da0060bcc4ae3b54fe2f4cfc64be5b4cce. SDK production remains
04201edc7711361279d8487b385bc8b0ca9c63c7. The
[gate register](release-gates.json) owns F01 status; the
[approved contract](../MULTI_SCENE_SUPPORT.md) owns product behavior.
[Navigation](NAVIGATION_API.md) and [Operations](OPERATIONS.md) retain the semantic
contracts and experimental evidence. This package selects a first-release proposal
from their alternatives without treating it as approval.

## Decision requested

Approve or amend these eight decisions as one bounded RFC direction. Record the
reviewer, date and approval reference before implementation. F01 closes when the
reviewed contract is implemented and verified, with an attributable disposition.
F02 documentation, F03 final platform matrix and F06 freeze retain their own gates.

| Decision | Proposed first-release contract | Evidence and decisive follow-up |
| --- | --- | --- |
| 1. Availability | New scene-targeted/semantic APIs remain iOS27+ and iOS-only; SDK remains iOS15+. Existing inferred/manual APIs remain available below27. Observation host initializer also requires compiler>=6.4, matching its guard. | Existing compatibility and call-site evidence; F03 compiles guarded callers and legacy paths. No wider pre27 multi-scene claim. |
| 2. Target and names | Promote RUMViewTarget.current(in:) and the 21 implemented Swift overloads below. Keep required view argument. RUMOperationViewTarget remains an experimental migration alias. Add no inferred/manual-key/controller factories. | T01–T07/T15 ownership evidence. Exact-key/controller factories stay outside this release rather than adding gates. |
| 3. Conformers | Extension-only overloads with existing private capabilities. Monitor honors targets; custom/NOP conformers invoke their existing inferred method once. No protocol witness or changed shared-monitor return type. | Existing forwarding/custom/NOP controls; F03 requires an external conformer using normal imports. Document the custom-conformer targeting limit. |
| 4. Objective-C | Promote the 20 targeted selectors and DDRUMViewTarget.currentInScene:, preserving names/conversions. Swift Error completion overload stays Swift-only. | Debug selector evidence; require Objective-C Release client and the off-main safety rule below before removing Debug guards. |
| 5. Semantic host | Promote RUMNavigationHost content-only, accepted-state Publisher and observingCurrentDestination initializers, plus RUMNavigationDestination and RUMNavigationMetadata. Keep standard navigation/presentation and customer-owned state. | R06 and EXP-147–154/168–174. No exactness claim for opaque local @State, render-time values or late callbacks. |
| 6. Adapter boundary | Keep RUMNavigationTransitions, RUMNavigationTransitionProviding, transitions host initializer, RUMNavigationStack and its presentation types experimental. Stable third-party adapters use the accepted-state Publisher host. | Retains the exercised container-independent path without freezing low-level prepare/commit/cancel or mirrored native-container APIs. No new primitive/dependency. |
| 7. Metadata/authority | Automatic type/enum-case metadata, sparse overrides, no serialized associated values/occurrence tokens/scene IDs. Authority starts after accepted materialization, stays container-local and releases at final teardown. | R02–R06 and D03/D07–D10. Document stable source, synchronous initial state and one atomic Observation property. |
| 8. Migration/ownership | Existing apps keep APIs/defaults. Exact integration is optional per router/container. Manual pairing uses scene/key; each Operation step resolves context; Resources capture at start. | [Assessment](ASSESSMENT.md) and T01–T15. No public RUM UUID, returned view handle, wire change, scene session, per-window CPU or route-proportional instrumentation. |

Approval record: **pending**.

## Objective-C safety before Release exposure

Current Debug selectors and the factory are @MainActor Swift entry points.
Main-thread smoke tests do not establish off-main Objective-C misuse safety.
This is an open F01 contract/check, not a demonstrated new SDK regression.

Proposed behavior: Objective-C entry shims check the calling thread before crossing
actor-isolated Swift entry or dereferencing UIKit. The factory returns nil off-main
with a nullable Objective-C result. Invalid off-main targeted calls are ignored
safely; they neither schedule a later UIKit read, retain the scene, synchronously
dispatch to main, nor silently retarget a different view. Main-thread behavior
keeps the exercised contract. Swift factories/overloads retain @MainActor.
Changing the experimental factory's nonnullable shape requires explicit approval.

Before promotion, an Objective-C Release fixture must invoke factory and
manual/telemetry companions on and off main: no SDK trap/deadlock, no UIKit
access/retention on invalid paths, and no foreign telemetry. Verify exactly-once
custom/NOP fallback on valid calls. If reviewers choose another rule, freeze its
decisive test before implementation.

## Swift target surface

Observed 21 experimental overloads in
[RUMMonitorProtocol+Convenience.swift](../Sources/RUMMonitorProtocol+Convenience.swift).
The proposal preserves signatures/defaults. All are iOS27+, @MainActor and
extension-only on RUMMonitorProtocol. RUMViewTarget captures only the scene
identifier on main; processing resolves its live current view. It is not a
snapshot of a view UUID.

~~~swift
public struct RUMViewTarget {
    @MainActor
    public static func current(in scene: UIWindowScene) -> Self
}
~~~

~~~swift
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

Unresolved targets retain independent inference and family-specific fallback.
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

Preserve these implemented initializer shapes and core defaults:

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
| Implement approved exposure/safety | SDK implementer | Recorded approval | Exact declarations and positive/negative forwarding/off-main controls | Xcode, simulator, Objective-C Release client |
| External conformer/guarded clients | SDK implementer | Approved exposure | Normal imports compile; old conformers/defaults work | Supported Swift/platform SDKs |
| API baselines and migration guide | SDK implementer | Reviewed declarations | Reviewed generated diff, compiling examples | Existing API tooling |
| Release acceptance | Gate owners | Recorded gate dependencies | F02/F03/F04/F05/F06 close on their own evidence | Review, CI, required hardware |

This decomposes F01's existing deliverable; it adds no gates or experiment quota.
Physical/Duo evidence remains mandatory regardless of API approval.

The repository [AGENTS.md](../../AGENTS.md) requires: “Do NOT introduce new public
API without RFC review.” The [development guide](../../docs/DEVELOPMENT.md#rfc-process-for-major-changes)
also requires internal RFC approval and cross-platform alignment for significant
public API changes. This is why a reviewer decision is required for promotion;
documentation preparation and existing experimental validation can continue.
