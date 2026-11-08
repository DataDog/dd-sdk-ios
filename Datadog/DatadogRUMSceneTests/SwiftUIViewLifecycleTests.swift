/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import UIKit
import SwiftUI
import Combine
@testable import TestUtilities
@_spi(Internal)
@testable import DatadogInternal
@_spi(Internal)
@testable import DatadogCore
@testable import DatadogRUM

#if os(iOS) && canImport(SwiftUI)
extension SwiftUINavigationOwnershipTests {
    @MainActor
    func testDisappearanceCallback_keepsItsRegistrationUntilReleaseAndStopsOnlyOnce() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Owned SwiftUI tracking requires iOS 27") }
        let core = makeHandoffCore()
        defer { core.stop() }
        let feature = try makeOwnedSwiftUIFeature(in: core)
        let binding = try XCTUnwrap(feature.instrumentation.swiftUIViewFoundation?.makeBinding())
        let scene = try connectedSceneIdentifier(binding)
        var holder: RUMSwiftUIViewTrackingEpoch? = RUMSwiftUIViewTrackingEpoch()
        weak var originalHolder = holder
        let callback = try XCTUnwrap(holder?.enter(binding))
        let admission = try XCTUnwrap(RUMSwiftUIViewCallbackAdmission(holder: try XCTUnwrap(holder), callback: callback))
        weak var originalSession = try XCTUnwrap(admission.withSession { $0 })
        _ = admission.withSession { session in
            _ = session.trackingState.update(attachment: .attached(scene))
            _ = session.trackingState.appear()
        }
        let identity = try XCTUnwrap(admission.withSession { $0.trackingState.identity })
        var transitions: [RUMViewTrackingState.Transition] = []
        var disappearance: (() -> Void)? = admission.disappearanceCallback {
            _ = admission.withSession { transitions += $0.trackingState.disappear() }
        }
        holder = nil
        XCTAssertNotNil(originalHolder)
        XCTAssertNotNil(originalSession)
        XCTAssertTrue(admission.isValid)
        try XCTUnwrap(disappearance)()
        XCTAssertEqual(transitions, [.stop(identity: identity, sceneIdentifier: scene)])
        try XCTUnwrap(disappearance)()
        XCTAssertEqual(transitions, [.stop(identity: identity, sceneIdentifier: scene)])
        disappearance = nil
        XCTAssertNil(originalHolder)
        XCTAssertNil(originalSession)
        XCTAssertFalse(admission.isValid)
        XCTAssertFalse(admission.fence.isActive)
    }

    @MainActor
    func testDisappearanceCallback_whenItsRegistrationRetires_itCannotMutateTheReplacement() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Owned SwiftUI tracking requires iOS 27") }
        let core = makeHandoffCore()
        defer { core.stop() }
        let feature = try makeOwnedSwiftUIFeature(in: core)
        let binding = try XCTUnwrap(feature.instrumentation.swiftUIViewFoundation?.makeBinding())
        let scene = try connectedSceneIdentifier(binding)
        let holder = RUMSwiftUIViewTrackingEpoch()
        let callback = try XCTUnwrap(holder.enter(binding))
        let admission = try XCTUnwrap(RUMSwiftUIViewCallbackAdmission(holder: holder, callback: callback))
        var admittedCalls = 0
        let disappearance = admission.disappearanceCallback {
            _ = admission.withSession {
                admittedCalls += 1
                _ = $0.trackingState.disappear()
            }
        }
        holder.retire(callback)
        let replacement = try XCTUnwrap(holder.enter(binding))
        let current = try XCTUnwrap(RUMSwiftUIViewCallbackAdmission(holder: holder, callback: replacement))
        _ = current.withSession { session in
            _ = session.trackingState.update(attachment: .attached(scene))
            _ = session.trackingState.appear()
        }
        let revision = try XCTUnwrap(current.withSession { $0.trackingState.revision })
        disappearance()
        XCTAssertEqual(admittedCalls, 0)
        XCTAssertFalse(admission.isValid)
        XCTAssertEqual(current.withSession { $0.trackingState.revision }, revision)
        XCTAssertEqual(current.withSession { $0.trackingState.isAppeared }, true)
        holder.retire(replacement)
    }

    @MainActor
    func testDisappearanceCallback_whenCoreStops_itDoesNotRetainTheOwnershipGraph() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Owned SwiftUI tracking requires iOS 27") }
        var core: DatadogCore? = makeHandoffCore()
        defer { core?.stop() }
        weak var originalCore = core
        var feature: RUMFeature? = try makeOwnedSwiftUIFeature(in: try XCTUnwrap(core))
        weak var originalFeature = feature
        weak var originalMonitor = feature?.monitor
        weak var originalFoundation = feature?.instrumentation.swiftUIViewFoundation
        let binding = try XCTUnwrap(feature?.instrumentation.swiftUIViewFoundation?.makeBinding())
        var holder: RUMSwiftUIViewTrackingEpoch? = RUMSwiftUIViewTrackingEpoch()
        weak var originalHolder = holder
        let callback = try XCTUnwrap(holder?.enter(binding))
        let admission = try XCTUnwrap(RUMSwiftUIViewCallbackAdmission(holder: try XCTUnwrap(holder), callback: callback))
        weak var originalSession = try XCTUnwrap(admission.withSession { $0 })
        let observer = RUMSceneIdentifierReader.ObserverView(
            admission: admission,
            onChange: { _ in },
            applicationSupportsMultipleScenes: true
        )
        let source = RUMSwiftUINavigationOccurrenceSource(binding: binding)
        var admittedCalls = 0
        var disappearance: (() -> Void)? = admission.disappearanceCallback {
            _ = admission.withSession { _ in admittedCalls += 1 }
        }
        holder = nil
        core?.flush()
        core?.stop()
        feature = nil
        core = nil
        await drainOwnedMainDelivery()
        XCTAssertNotNil(originalHolder)
        XCTAssertNil(originalCore)
        XCTAssertNil(originalFeature)
        XCTAssertNil(originalMonitor)
        XCTAssertNil(originalFoundation)
        XCTAssertFalse(binding.isValid)
        try XCTUnwrap(disappearance)()
        XCTAssertEqual(admittedCalls, 0)
        disappearance = nil
        withExtendedLifetime((observer, source, admission)) {
            XCTAssertNil(originalHolder)
            XCTAssertNil(originalSession)
        }
    }

    @MainActor
    func testOrdinaryTrackedView_preservesItsOccurrenceAndRoutesEventsToItsHostScene() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Owned SwiftUI tracking requires iOS 27") }
        let expectedDelegate = try XCTUnwrap(NSClassFromString(
            "RUMSceneTestHost.RUMTestSceneDelegate"
        ))
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.filter {
            $0.activationState != .unattached && $0.delegate.map {
                ObjectIdentifier(type(of: $0)) == ObjectIdentifier(expectedDelegate)
            } == true
        }
        XCTAssertEqual(scenes.count, 1)
        let scene = try XCTUnwrap(scenes.first)
        let delegate = try XCTUnwrap(scene.delegate as? UIWindowSceneDelegate)
        let window = try XCTUnwrap(delegate.window ?? nil)
        let originalRoot = try XCTUnwrap(window.rootViewController)
        let originalHidden = window.isHidden
        let originalKey = scene.windows.first(where: \.isKeyWindow)
        let sceneID = RUMSceneIdentifier(rawValue: scene.session.persistentIdentifier)
        let rows = OrdinarySwiftUIViewRows()
        let core = DatadogCore(
            directory: temporaryCoreDirectory, dateProvider: SystemDateProvider(), initialConsent: .granted,
            performance: .mockAny(), httpClient: HTTPClientMock(), encryption: nil,
            contextProvider: .mockAny(), applicationVersion: .mockAny(),
            maxBatchesPerUpload: 1, backgroundTasksEnabled: false
        )
        defer { core.stop() }
        let date = Date()
        core.contextProvider.write { context in
            context = .mockWith(
                sdkInitDate: date,
                launchInfo: .mockWith(launchReason: .userLaunch, processLaunchDate: date),
                applicationStateHistory: .mockWith(initialState: .active, date: date)
            )
        }
        core.flush()
        var config = RUM.Configuration(applicationID: "ordinary-owned-swiftui", trackAnonymousUser: false)
        config.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
        config.featureFlags = [.multiSceneTracking: true]
        config.sessionSampleRate = 100
        config.vitalsUpdateFrequency = nil
        config.viewEventMapper = { rows.append($0); return $0 }
        try RUM.enableOrThrow(with: config, in: core)
        let feature = try XCTUnwrap(core.get(feature: RUMFeature.self))
        XCTAssertNotNil(feature.instrumentation.swiftUIViewFoundation)
        guard RUMSwiftUIViewCallbackAdmission.lifecycleObserver == nil else {
            XCTFail("An unrelated SwiftUI lifecycle observer is already installed")
            return
        }
        var observationBoundary = "mount"
        var lifecycleObservations: [OrdinarySwiftUILifecycleObservation] = []
        var droppedLifecycleObservations = 0
        var mountedRegistrationIdentifier: UUID?
        var mountedFoundationEpoch: UUID?
        var mountedTrackingIdentity: String?
        RUMSwiftUIViewCallbackAdmission.lifecycleObserver = { observation in
            if lifecycleObservations.count < 256 {
                lifecycleObservations.append(.init(
                    sequence: lifecycleObservations.count,
                    boundary: observationBoundary,
                    observation: observation
                ))
            } else {
                droppedLifecycleObservations += 1
            }
        }
        var boundaries: [[String: Any]] = []
        var firstDriver: OrdinarySwiftUIViewDriver? = OrdinarySwiftUIViewDriver()
        var secondDriver: OrdinarySwiftUIViewDriver?
        defer {
            RUMSwiftUIViewCallbackAdmission.lifecycleObserver = nil
            firstDriver?.update = nil
            secondDriver?.update = nil
            window.rootViewController = originalRoot
            window.isHidden = originalHidden
            originalKey?.makeKey()
        }
        let driver = try XCTUnwrap(firstDriver)
        let child = OrdinarySwiftUIViewChild(driver: driver)
        let expectedPath = "OnTracked/\(child.typeDescription.hashValue)"
        let tracked = AnyView(child.trackRUMView(name: "OnTracked", attributes: ["probe": "on", "sample": 7], in: core))
        let host = UIHostingController(rootView: OrdinarySwiftUIViewRoot(content: tracked, driver: driver))
        window.rootViewController = host
        window.makeKeyAndVisible()
        func snapshot() -> RUMCoreContext? { feature.monitor.rumContextSnapshot(for: .scene(sceneID)) }
        func selectedViews(_ ids: Set<String>) -> [RUMViewEvent] {
            rows.views.filter { ids.contains($0.view.id) || $0.view.name == "OnTracked" }
        }
        func record(_ phase: String, _ expectedHost: UIViewController) {
            XCTAssertTrue(window.windowScene === scene)
            XCTAssertTrue(scene.windows.contains { $0 === window })
            XCTAssertTrue(window.rootViewController === expectedHost)
            XCTAssertTrue(window.isKeyWindow)
            XCTAssertFalse(window.isHidden)
            XCTAssertTrue(window.bounds.width.isFinite && window.bounds.height.isFinite
                          && window.bounds.width > 0 && window.bounds.height > 0)
            let context = snapshot()
            boundaries.append([
                "phase": phase, "scene_identifier": scene.session.persistentIdentifier,
                "window_identity": String(describing: ObjectIdentifier(window)),
                "root_identity": String(describing: ObjectIdentifier(expectedHost)),
                "is_key": window.isKeyWindow, "visible": !window.isHidden,
                "scene_matches": window.windowScene === scene,
                "root_matches": window.rootViewController === expectedHost,
                "width": Double(window.bounds.width), "height": Double(window.bounds.height),
                "context": context.map {
                    ["session_id": $0.sessionID, "view_id": $0.viewID ?? "",
                     "name": $0.viewName ?? "", "path": $0.viewPath ?? ""]
                } ?? [:]
            ])
        }
        var attemptedBoundary = "mount"
        var observedViewIDs: [String] = []
        var terminalCaptured = false
        defer {
            if !terminalCaptured {
                do {
                    let context = snapshot()
                    let raw = rows.views
                    let encoded = try raw.map {
                        try JSONSerialization.jsonObject(with: JSONEncoder().encode($0))
                    }
                    let partial: [String: Any] = [
                        "schema_version": 1, "family": "swiftui-on-public-entry-partial",
                        "terminal": false, "attempted_boundary": attemptedBoundary,
                        "scene_identifier": scene.session.persistentIdentifier,
                        "stable_states": driver.states,
                        "reconstructed_states": secondDriver?.states ?? [],
                        "first_disappearances": driver.disappearances,
                        "second_disappearances": secondDriver?.disappearances ?? 0,
                        "scene_view_absent": context?.viewID == nil,
                        "first_view_inactive": observedViewIDs.first.map { id in
                            raw.contains { $0.view.id == id && $0.view.isActive == false }
                        } ?? false,
                        "observed_view_ids": observedViewIDs,
                        "context": context.map {
                            ["session_id": $0.sessionID, "view_id": $0.viewID ?? "",
                             "name": $0.viewName ?? "", "path": $0.viewPath ?? ""]
                        } ?? [:],
                        "boundaries": boundaries, "view_rows": encoded,
                        "lifecycle_observations": try JSONSerialization.jsonObject(
                            with: JSONEncoder().encode(lifecycleObservations)
                        ),
                        "dropped_lifecycle_observations": droppedLifecycleObservations,
                        "lifecycle_observer_installed": RUMSwiftUIViewCallbackAdmission.lifecycleObserver != nil,
                        "mounted_registration_identifier": mountedRegistrationIdentifier?.uuidString ?? "",
                        "mounted_foundation_epoch": mountedFoundationEpoch?.uuidString ?? "",
                        "mounted_tracking_identity": mountedTrackingIdentity ?? "",
                        "window_is_key": window.isKeyWindow,
                        "window_visible": !window.isHidden,
                        "window_scene_matches": window.windowScene === scene,
                        "root_is_original_host": window.rootViewController === host,
                        "window_width": Double(window.bounds.width),
                        "window_height": Double(window.bounds.height)
                    ]
                    let capture = XCTAttachment(
                        data: try JSONSerialization.data(withJSONObject: partial),
                        uniformTypeIdentifier: "public.json"
                    )
                    capture.name = "ordinary-swiftui-public-entry-partial"
                    capture.lifetime = .keepAlways
                    add(capture)
                } catch {
                    XCTFail("Could not retain ordinary SwiftUI partial observations")
                }
            }
        }
        try await awaitOrdinaryBoundary("mount", core: core) {
            driver.states == [0] && snapshot()?.viewName == "OnTracked"
                && rows.views.contains { $0.view.isActive == true }
        }
        let first = try XCTUnwrap(snapshot())
        let firstID = try XCTUnwrap(first.viewID)
        observedViewIDs.append(firstID)
        let mountedObservation = lifecycleObservations.first {
            $0.boundary == "mount" && $0.observation.phase == "trait-publisher-call"
                && $0.observation.transitions.contains { $0.kind == "start" }
        }?.observation
        mountedRegistrationIdentifier = mountedObservation?.registrationIdentifier
        mountedFoundationEpoch = mountedObservation?.foundationEpoch
        mountedTrackingIdentity = mountedObservation?.trackingIdentity
        XCTAssertEqual(first.viewPath, expectedPath)
        XCTAssertEqual(Set(selectedViews([firstID]).map { $0.view.id }), [firstID])
        record("mount", host)
        observationBoundary = "child-state-update"
        try XCTUnwrap(driver.update)()
        attemptedBoundary = "child-state-update"
        try await awaitOrdinaryBoundary("child-state-update", core: core) { driver.states == [0, 1] }
        let retained = try XCTUnwrap(snapshot())
        XCTAssertEqual(retained.sessionID, first.sessionID)
        XCTAssertEqual(retained.viewID, firstID)
        XCTAssertEqual(retained.viewName, first.viewName)
        XCTAssertEqual(retained.viewPath, expectedPath)
        XCTAssertEqual(Set(selectedViews([firstID]).map { $0.view.id }), [firstID])
        record("child-state-update", host)
        observationBoundary = "unmount"
        driver.visible = false
        attemptedBoundary = "unmount"
        try await awaitOrdinaryBoundary("unmount", core: core) {
            driver.disappearances == 1 && snapshot()?.viewID == nil
                && rows.views.contains { $0.view.id == firstID && $0.view.isActive == false }
        }
        XCTAssertNil(snapshot())
        record("unmount", host)
        driver.update = nil
        firstDriver = nil
        let next = OrdinarySwiftUIViewDriver()
        secondDriver = next
        let rebuilt = AnyView(OrdinarySwiftUIViewChild(driver: next).trackRUMView(
            name: "OnTracked", attributes: ["probe": "on", "sample": 7], in: core
        ))
        let nextHost = UIHostingController(rootView: OrdinarySwiftUIViewRoot(content: rebuilt, driver: next))
        observationBoundary = "reconstruction"
        window.rootViewController = nextHost
        attemptedBoundary = "reconstruction"
        try await awaitOrdinaryBoundary("reconstruction", core: core) {
            next.states == [0] && snapshot()?.viewName == "OnTracked" && snapshot()?.viewID != firstID
        }
        let second = try XCTUnwrap(snapshot())
        let secondID = try XCTUnwrap(second.viewID)
        observedViewIDs.append(secondID)
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertEqual(second.sessionID, first.sessionID)
        XCTAssertEqual(second.viewPath, expectedPath)
        record("reconstruction", nextHost)
        observationBoundary = "reconstructed-unmount"
        next.visible = false
        attemptedBoundary = "reconstructed-unmount"
        try await awaitOrdinaryBoundary("reconstructed-unmount", core: core) {
            next.disappearances == 1 && snapshot()?.viewID == nil
                && rows.views.contains { $0.view.id == secondID && $0.view.isActive == false }
        }
        XCTAssertNil(snapshot())
        record("reconstructed-unmount", nextHost)
        next.update = nil
        let raw = rows.views
        let expectedViewIDs: Set<String> = [firstID, secondID]
        let selectedIndices = raw.indices.filter {
            expectedViewIDs.contains(raw[$0].view.id) || raw[$0].view.name == "OnTracked"
        }
        let actual = selectedIndices.map { raw[$0] }
        XCTAssertEqual(Set(actual.map { $0.view.id }), [firstID, secondID])
        for value in actual {
            XCTAssertEqual(value.session.id, first.sessionID)
        }
        let selectedEncoded: [[String: Any]] = try actual.map {
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode($0))
            let row = try XCTUnwrap(object as? [String: Any])
            let context = try XCTUnwrap(row["context"] as? [String: Any])
            XCTAssertEqual(context["probe"] as? String, "on")
            XCTAssertEqual(context["sample"] as? Int, 7)
            XCTAssertEqual($0.view.name, "OnTracked")
            XCTAssertEqual($0.view.url, expectedPath)
            return row
        }
        let encoded: [[String: Any]] = try raw.map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) as? [String: Any])
        }
        let payload: [String: Any] = [
            "schema_version": 1, "family": "swiftui-on-public-entry", "terminal": true,
            "scene_identifier": scene.session.persistentIdentifier,
            "expected_path": expectedPath, "stable_states": driver.states,
            "reconstructed_states": next.states, "boundaries": boundaries, "view_rows": encoded,
            "lifecycle_observations": try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(lifecycleObservations)
            ),
            "dropped_lifecycle_observations": droppedLifecycleObservations,
            "lifecycle_observer_installed": RUMSwiftUIViewCallbackAdmission.lifecycleObserver != nil,
            "mounted_registration_identifier": mountedRegistrationIdentifier?.uuidString ?? "",
            "mounted_foundation_epoch": mountedFoundationEpoch?.uuidString ?? "",
            "mounted_tracking_identity": mountedTrackingIdentity ?? "",
            "selected_view_row_indices": selectedIndices, "selected_view_rows": selectedEncoded,
            "mounted_session_id": first.sessionID, "expected_view_ids": [firstID, secondID]
        ]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: payload), uniformTypeIdentifier: "public.json")
        attachment.name = "ordinary-swiftui-public-entry-terminal"
        attachment.lifetime = .keepAlways
        add(attachment)
        terminalCaptured = true
    }

    @MainActor
    func awaitOrdinaryBoundary(
        _ name: String, core: DatadogCore, condition: () -> Bool
    ) async throws {
        let watchdog = Date().addingTimeInterval(20)
        while Date() < watchdog {
            core.flush()
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Missing ordinary SwiftUI boundary: \(name)")
        throw OrdinarySwiftUIViewCaptureError.missingBoundary(name)
    }
}

enum OrdinarySwiftUIViewCaptureError: Error { case missingBoundary(String) }

private struct OrdinarySwiftUILifecycleObservation: Encodable {
    let sequence: Int
    let boundary: String
    let observation: RUMSwiftUIViewCallbackAdmission.LifecycleObservation
}

private final class OrdinarySwiftUIViewRows: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [RUMViewEvent] = []
    func append(_ value: RUMViewEvent) { lock.lock(); defer { lock.unlock() }; values.append(value) }
    var views: [RUMViewEvent] {
        lock.lock(); defer { lock.unlock() }
        return values
    }
}

@MainActor
final class OrdinarySwiftUIViewDriver: ObservableObject {
    @Published var visible = true
    var states: [Int] = []
    var disappearances = 0
    var update: (() -> Void)?
}

struct OrdinarySwiftUIViewChild: View {
    let driver: OrdinarySwiftUIViewDriver
    @State private var counter = 0
    var body: some View {
        Text("Counter \(counter)")
            .onAppear { driver.states.append(counter); driver.update = { counter += 1 } }
            .onChange(of: counter) { driver.states.append($0) }
            .onDisappear { driver.disappearances += 1 }
    }
}

private struct OrdinarySwiftUIViewRoot: View {
    let content: AnyView
    @ObservedObject var driver: OrdinarySwiftUIViewDriver
    var body: some View { if driver.visible { content } }
}
#endif
