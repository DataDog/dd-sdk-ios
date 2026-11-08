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
    func testSceneDestruction_whenLastHostIsReleased_itReleasesOwnershipWithoutAdoptingPeer() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Owned SwiftUI tracking requires iOS 27") }
        // Off qualifies the same OS and fixture release boundary before On is interpreted.
        for enabled in [false, true] {
            try await exerciseLastSceneHostRelease(multiSceneEnabled: enabled)
        }
    }

    @MainActor
    private func exerciseLastSceneHostRelease(multiSceneEnabled: Bool) async throws {
        let application = UIApplication.shared
        let delegateClass: AnyClass = try XCTUnwrap(NSClassFromString("RUMSceneTestHost.RUMTestSceneDelegate"))
        let ownedScenes = application.connectedScenes.compactMap { $0 as? UIWindowScene }.filter {
            $0.delegate.map { ObjectIdentifier(type(of: $0)) == ObjectIdentifier(delegateClass) } == true
        }
        let sceneA = try XCTUnwrap(
            ownedScenes.count == 1 ? ownedScenes.first : nil,
            "The case requires one original fixture scene"
        )
        try requireSceneHost(application.supportsMultipleScenes, "The host must support real scene creation")
        let originalSessionIDs = Set(application.openSessions.map(\.persistentIdentifier))
        let mode = multiSceneEnabled ? "on" : "off"
        let rows = SceneHostLifetimeRows()
        let observations = SceneHostLifetimeNotifications()
        var core: DatadogCore? = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .mockAny(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: 1,
            backgroundTasksEnabled: false
        )
        weak var originalCore = core
        var feature: RUMFeature?
        weak var originalFeature: RUMFeature?
        weak var originalMonitor: Monitor?
        weak var originalFoundation: RUMSwiftUIViewFoundation?
        var hostA: SceneHostLifetimeWindow?
        var hostB: SceneHostLifetimeWindow?
        var retainedCallback: SceneHostLifetimeCallback?
        var terminal = false
        var boundary = "mount-A"
        var pendingOwner: SceneHostResourceOwner?
        defer {
            let payload: [String: Any] = [
                "mode": mode, "terminal": terminal, "boundary": boundary,
                "scene_A": hostA?.identifier ?? "", "scene_B": hostB?.identifier ?? "",
                "notifications": observations.records,
                "recorded_created_sessions": Array(observations.createdSceneIdentifiers).sorted(),
                "request_errors": observations.requestErrors,
                "B_window_released": hostB?.releasedWindow == nil,
                "B_controller_released": hostB?.releasedController == nil,
                "B_hosting_view_released": hostB?.releasedHostingView == nil,
                "pending_resource_owner": pendingOwner.map {
                    [
                        "session_id": $0.sessionID, "view_id": $0.viewID, "scene_id": $0.sceneID,
                        "resource_id": $0.resourceID, "view_name": $0.viewName,
                    ]
                } ?? [:],
                "A_initial_topology": hostA?.initialTopology ?? [:],
                "B_initial_topology": hostB?.initialTopology ?? [:],
            ]
            do {
                var captured = payload
                captured["view_rows"] = try rows.views.map {
                    try JSONSerialization.jsonObject(with: JSONEncoder().encode($0))
                }
                captured["resource_rows"] = try rows.resources.map {
                    try JSONSerialization.jsonObject(with: JSONEncoder().encode($0))
                }
                captured["action_rows"] = try rows.actions.map {
                    try JSONSerialization.jsonObject(with: JSONEncoder().encode($0))
                }
                let attachment = XCTAttachment(
                    data: try JSONSerialization.data(withJSONObject: captured),
                    uniformTypeIdentifier: "public.json"
                )
                attachment.name = "last-scene-host-" + mode + (terminal ? "-terminal" : "-partial")
                attachment.lifetime = .keepAlways
                add(attachment)
            } catch {
                XCTFail("Could not preserve last-scene-host observations")
            }
            retainedCallback?.release()
            hostB?.cleanupAfterFailure()
            hostA?.release(destroyed: false)
            observations.stop()
            core?.stop()
        }

        addTeardownBlock { [weak self, observations] in
            guard let self else {
                return
            }
            try await self.cleanupSceneHostSessions(observations, originalSessionIDs: originalSessionIDs)
        }
        let date = Date()
        core?.contextProvider.write { context in
            context = .mockWith(
                sdkInitDate: date,
                launchInfo: .mockWith(launchReason: .userLaunch, processLaunchDate: date),
                applicationStateHistory: .mockWith(initialState: .active, date: date)
            )
        }
        core?.flush()
        var configuration = RUM.Configuration(applicationID: "last-scene-host-" + mode, trackAnonymousUser: false)
        configuration.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
        configuration.featureFlags = [.multiSceneTracking: multiSceneEnabled]
        configuration.sessionSampleRate = 100
        configuration.vitalsUpdateFrequency = nil
        configuration.viewEventMapper = {
            rows.append($0)
            return $0
        }
        configuration.resourceEventMapper = {
            rows.append($0)
            return $0
        }
        configuration.actionEventMapper = {
            rows.append($0)
            return $0
        }
        try RUM.enableOrThrow(with: configuration, in: try XCTUnwrap(core))
        feature = core?.get(feature: RUMFeature.self)
        originalFeature = feature
        originalMonitor = feature?.monitor
        originalFoundation = feature?.instrumentation.swiftUIViewFoundation
        try requireSceneHost(feature?.monitor.isMultiSceneTrackingEnabled == multiSceneEnabled, "Resolved feature flag")

        hostA = try SceneHostLifetimeWindow(
            scene: sceneA,
            core: try XCTUnwrap(core),
            name: "Lifetime A " + mode,
            restoresOriginal: true
        )
        try await awaitSceneHostBoundary(boundary, core: core) {
            rows.views.contains { $0.view.name == "Lifetime A " + mode && $0.view.isActive == true }
        }
        if multiSceneEnabled {
            try requireSceneHost(
                feature?.monitor.rumContextSnapshot(
                    for: .scene(RUMSceneIdentifier(rawValue: sceneA.session.persistentIdentifier))
                )?.viewName == "Lifetime A " + mode,
                "Positive original A owner"
            )
        }

        boundary = "native-create-B"
        let request = UISceneSessionActivationRequest(
            userActivity: NSUserActivity(activityType: "com.datadoghq.tests.scene-lifetime")
        )
        application.activateSceneSession(for: request) { error in observations.recordRequestError(error) }
        try await awaitSceneHostBoundary(boundary, core: core) {
            !observations.requestErrors.isEmpty
                || application.connectedScenes.contains {
                    !originalSessionIDs.contains($0.session.persistentIdentifier)
                        && $0.activationState != .unattached
                }
        }
        try requireSceneHost(observations.requestErrors.isEmpty, "Native scene creation request")
        // This short scope owns the scene only while installing the fixture's B host.
        hostB = try makeCreatedSceneHostWindow(
            originalSessionIDs: originalSessionIDs,
            core: XCTUnwrap(core),
            name: "Lifetime B " + mode,
            observations: observations
        )
        let b = try XCTUnwrap(hostB)
        let bID = RUMSceneIdentifier(rawValue: b.identifier)
        try requireSceneHost(
            observations.contains(UIScene.willConnectNotification, scene: b.identifier),
            "OS-delivered B connection"
        )
        boundary = "positive-B-admission"
        try await awaitSceneHostBoundary(boundary, core: core) {
            rows.views.contains { $0.view.name == "Lifetime B " + mode && $0.view.isActive == true }
        }
        if multiSceneEnabled {
            try requireSceneHost(
                feature?.monitor.rumContextSnapshot(for: .scene(bID))?.viewName == "Lifetime B " + mode,
                "Positive admitted B SDK View"
            )
            retainedCallback = try SceneHostLifetimeCallback(
                binding: XCTUnwrap(feature?.instrumentation.swiftUIViewFoundation?.makeBinding()),
                scene: bID
            )
            try requireSceneHost(
                retainedCallback?.admitsOriginalScene == true,
                "Retained callback positively admits B before destruction"
            )
        }
        let resourceKey = "last-host-" + UUID().uuidString
        let resourceURL = "https://example.invalid/last-scene-host/" + resourceKey
        feature?.monitor.startResource(
            resourceKey: resourceKey,
            httpMethod: .get,
            urlString: resourceURL,
            attributes: [:],
            explicitTarget: .scene(bID)
        )
        core?.flush()
        let owners = await pendingSceneHostResource(resourceKey, monitor: try XCTUnwrap(feature?.monitor))
        pendingOwner = try XCTUnwrap(owners.count == 1 ? owners.first : nil, "Exactly one admitted pending Resource")
        let owner = try XCTUnwrap(pendingOwner)
        try requireSceneHost(owner.viewName == "Lifetime B " + mode, "Resource actually started on B")
        if multiSceneEnabled {
            try requireSceneHost(owner.sceneID == b.identifier, "Independent pending Resource scene owner")
            try requireSceneHost(
                owner.viewID == feature?.monitor.rumContextSnapshot(for: .scene(bID))?.viewID,
                "Pending Resource and admitted B View have the same owner"
            )
        }
        try requireSceneHost(rows.resources.isEmpty, "Resource remains pending before destruction")
        try requireSceneHost(
            b.releasedWindow != nil && b.releasedController != nil && b.releasedHostingView != nil,
            "All weak UI observations start non-nil"
        )
        boundary = "native-destroy-B"
        try requestSceneHostDestruction(b.identifier, observations: observations)
        try await awaitSceneHostBoundary(boundary, core: core) {
            !observations.requestErrors.isEmpty
                || (observations.contains(UIScene.didDisconnectNotification, scene: b.identifier)
                    && !application.connectedScenes.contains { $0.session.persistentIdentifier == b.identifier }
                    && !application.openSessions.contains { $0.persistentIdentifier == b.identifier })
        }
        try requireSceneHost(observations.requestErrors.isEmpty, "Native destruction request")
        b.relinquishDestroyedReferences()
        boundary = "A-return-and-live-work"
        application.activateSceneSession(for: UISceneSessionActivationRequest(session: sceneA.session)) { error in
            observations.recordRequestError(error)
        }
        let aID = RUMSceneIdentifier(rawValue: sceneA.session.persistentIdentifier)
        try await awaitSceneHostBoundary(boundary, core: core) {
            guard sceneA.activationState == .foregroundActive else {
                return false
            }
            if multiSceneEnabled {
                return feature?.monitor.rumContextSnapshot(for: .scene(aID))?.viewName == "Lifetime A " + mode
            }
            return hostA?.releasedWindow?.windowScene === sceneA
                && hostA?.releasedController != nil
        }
        try requireSceneHost(observations.requestErrors.isEmpty, "A reactivation request")
        let aOwner = multiSceneEnabled ? feature?.monitor.rumContextSnapshot(for: .scene(aID))?.viewID : nil
        if multiSceneEnabled {
            feature?.monitor.addAction(
                type: .custom,
                name: "A survives B " + mode,
                attributes: [:],
                explicitTarget: .scene(aID)
            )
            try await awaitSceneHostBoundary(boundary, core: core) {
                rows.actions.contains { $0.action.target?.name == "A survives B " + mode }
            }
            let actions = rows.actions.filter { $0.action.target?.name == "A survives B " + mode }
            try requireSceneHost(
                actions.count == 1 && actions.first?.view.id == aOwner,
                "Surviving A work has its own positive View owner"
            )
        }
        boundary = "last-B-host-release-with-resource-held"
        try await awaitSceneHostBoundary(boundary, core: core) {
            b.releasedWindow == nil && b.releasedController == nil && b.releasedHostingView == nil
        }
        let stillPending = await pendingSceneHostResource(resourceKey, monitor: try XCTUnwrap(feature?.monitor))
        try requireSceneHost(stillPending == [owner] && rows.resources.isEmpty, "Original B Resource is still pending")
        try requireSceneHost(
            originalCore != nil && originalFeature != nil && originalMonitor != nil,
            "Original SDK and peer A remain alive at the UI release boundary"
        )
        if multiSceneEnabled {
            try requireSceneHost(
                retainedCallback?.holder != nil && retainedCallback?.session != nil,
                "Retained callback registration is still held"
            )
            retainedCallback?.invoke()
            try requireSceneHost(retainedCallback?.calls == 0, "Disconnected callback cannot adopt peer A")
            try requireSceneHost(
                feature?.monitor.rumContextSnapshot(for: .scene(aID))?.viewID == aOwner,
                "Stale callback preserves A's current owner"
            )
        }
        boundary = "complete-captured-B-resource"
        feature?.monitor.stopResource(resourceKey: resourceKey, statusCode: 200, kind: .xhr, size: 1, attributes: [:])
        try await awaitSceneHostBoundary(boundary, core: core) {
            rows.resources.contains { $0.resource.url == resourceURL }
        }
        let resources = rows.resources.filter { $0.resource.url == resourceURL }
        try requireSceneHost(
            resources.count == 1 && resources.first?.view.id == owner.viewID
                && resources.first?.session.id == owner.sessionID
                && resources.first?.resource.id == owner.resourceID,
            "Completion keeps the independently captured B start ownership"
        )
        hostA?.release(destroyed: false)
        boundary = "original-Core-release"
        core?.flush()
        core?.stop()
        feature = nil
        core = nil
        try await awaitSceneHostBoundary(boundary) {
            originalCore == nil && originalFeature == nil && originalMonitor == nil && originalFoundation == nil
        }
        retainedCallback?.invoke()
        try requireSceneHost(retainedCallback?.calls ?? 0 == 0, "Retained callback remains inert after Core release")
        retainedCallback?.release()
        try requireSceneHost(
            retainedCallback?.holder == nil && retainedCallback?.session == nil,
            "Callback release releases its registration"
        )
        try requireSceneHost(observations.requestErrors.isEmpty, "No late native request errors")
        terminal = true
    }

    @MainActor
    private func makeCreatedSceneHostWindow(
        originalSessionIDs: Set<String>,
        core: DatadogCore,
        name: String,
        observations: SceneHostLifetimeNotifications
    ) throws -> SceneHostLifetimeWindow {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.filter {
            !originalSessionIDs.contains($0.session.persistentIdentifier)
        }
        let scene = try XCTUnwrap(scenes.count == 1 ? scenes.first : nil, "Exactly one new OS scene")
        let expectedDelegate: AnyClass = try XCTUnwrap(NSClassFromString("RUMSceneTestHost.RUMTestSceneDelegate"))
        try requireSceneHost(
            scene.delegate.map {
                ObjectIdentifier(type(of: $0)) == ObjectIdentifier(expectedDelegate)
            } == true,
            "Created scene belongs to the source-owned host delegate"
        )
        try requireSceneHost(scene.activationState != .unattached, "New B is actually connected")
        observations.recordCreatedScene(scene.session.persistentIdentifier)
        return try SceneHostLifetimeWindow(scene: scene, core: core, name: name, restoresOriginal: false)
    }

    @MainActor
    private func requestSceneHostDestruction(
        _ identifier: String,
        observations: SceneHostLifetimeNotifications
    ) throws {
        // Keep the OS session out of the suspended test frame and weak-release interval.
        let session = try XCTUnwrap(
            UIApplication.shared.openSessions.first {
                $0.persistentIdentifier == identifier
            }
        )
        UIApplication.shared.requestSceneSessionDestruction(session, options: nil) { error in
            observations.recordRequestError(error)
        }
    }

    @MainActor
    private func cleanupSceneHostSessions(
        _ observations: SceneHostLifetimeNotifications,
        originalSessionIDs: Set<String>
    ) async throws {
        let created = Set(
            observations.records.filter {
                $0["notification"] == UIScene.willConnectNotification.rawValue
            }
            .compactMap { $0["scene"] }
        ).union(observations.createdSceneIdentifiers).subtracting(originalSessionIDs)
        var state = "NO_RECORDED_NEW_SESSION"
        defer {
            let payload: [String: Any] = [
                "state": state, "recorded_new_sessions": Array(created).sorted(),
                "current_connected_sessions": UIApplication.shared.connectedScenes.map {
                    $0.session.persistentIdentifier
                }
                .sorted(),
                "current_open_sessions": UIApplication.shared.openSessions.map(\.persistentIdentifier).sorted(),
                "scope": "Test teardown only; original scenario and outer task-app cleanup stay separate",
            ]
            do {
                let attachment = XCTAttachment(
                    data: try JSONSerialization.data(withJSONObject: payload),
                    uniformTypeIdentifier: "public.json"
                )
                attachment.name = "last-scene-host-session-cleanup"
                attachment.lifetime = .keepAlways
                add(attachment)
            } catch {
                XCTFail("Could not preserve scene session cleanup observations")
            }
        }
        try requireSceneHost(created.count <= 1, "Ambiguous new session; outer task-app cleanup required")
        for identifier in created {
            try requireSceneHost(!originalSessionIDs.contains(identifier), "Never destroy an original session")
            state = "CLEANUP_INCOMPLETE"
            if UIApplication.shared.openSessions.contains(where: { $0.persistentIdentifier == identifier }) {
                try requestSceneHostDestruction(identifier, observations: observations)
            }
            try await awaitSceneHostBoundary("test-owned-session-cleanup") {
                !UIApplication.shared.connectedScenes.contains { $0.session.persistentIdentifier == identifier }
                    && !UIApplication.shared.openSessions.contains { $0.persistentIdentifier == identifier }
            }
            state = "RECORDED_NEW_SESSION_ABSENT"
        }
    }

    @MainActor
    private func pendingSceneHostResource(_ key: String, monitor: Monitor) async -> [SceneHostResourceOwner] {
        await withCheckedContinuation { continuation in
            monitor.featureScope.eventWriteContext { _, _ in
                let owners = monitor.applicationScope.sessionScopes.flatMap { session in
                    session.viewScopes.compactMap { view -> SceneHostResourceOwner? in
                        guard let resource = view.resourceScopes[key] else {
                            return nil
                        }
                        return .init(
                            sessionID: session.sessionUUID.toRUMDataFormat,
                            viewID: view.viewUUID.toRUMDataFormat,
                            sceneID: view.sceneIdentifier?.rawValue ?? "",
                            resourceID: resource.resourceUUID.toRUMDataFormat,
                            viewName: view.viewName
                        )
                    }
                }
                continuation.resume(returning: owners)
            }
        }
    }

    @MainActor
    private func awaitSceneHostBoundary(
        _ name: String,
        core: DatadogCore? = nil,
        condition: () -> Bool
    ) async throws {
        let watchdog = Date().addingTimeInterval(60)
        while Date() < watchdog {
            core?.flush()
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try requireSceneHost(false, "Missing last-host boundary: " + name)
    }

    private func requireSceneHost(_ condition: Bool, _ message: String) throws {
        guard condition else {
            XCTFail(message)
            throw OrdinarySwiftUIViewCaptureError.missingBoundary(message)
        }
    }

    private struct SceneHostResourceOwner: Equatable {
        let sessionID: String
        let viewID: String
        let sceneID: String
        let resourceID: String
        let viewName: String
    }

    @MainActor
    private final class SceneHostLifetimeWindow {
        let identifier: String
        let initialTopology: [String: String]
        weak var releasedWindow: UIWindow?
        weak var releasedController: UIViewController?
        weak var releasedHostingView: UIView?
        private weak var scene: UIWindowScene?
        private var window: UIWindow?
        private var controller: UIViewController?
        private var originalRoot: UIViewController?

        init(scene: UIWindowScene, core: DatadogCore, name: String, restoresOriginal: Bool) throws {
            let delegate = try XCTUnwrap(scene.delegate as? UIWindowSceneDelegate)
            let window = try XCTUnwrap(delegate.window ?? nil)
            identifier = scene.session.persistentIdentifier
            self.scene = scene
            self.window = window
            originalRoot = restoresOriginal ? window.rootViewController : nil
            let previousRoot = window.rootViewController
            let previousHidden = window.isHidden
            let previousKey = scene.keyWindow
            var installed = false
            defer {
                if !installed {
                    window.rootViewController = previousRoot
                    window.isHidden = previousHidden
                    previousKey?.makeKey()
                }
            }
            let host = UIHostingController(rootView: AnyView(Text(name).trackRUMView(name: name, in: core)))
            controller = host
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.loadViewIfNeeded()
            _ = try XCTUnwrap(
                window.windowScene === scene
                    && scene.windows.contains(where: { $0 === window })
                    && window.rootViewController === host
                    && window.isKeyWindow && !window.isHidden
                    && window.bounds.width.isFinite && window.bounds.height.isFinite
                    && window.bounds.width > 0 && window.bounds.height > 0 ? true : nil,
                "Source-owned real window, installed controller and display geometry"
            )
            initialTopology = [
                "scene": identifier, "window": String(describing: ObjectIdentifier(window)),
                "controller": String(describing: ObjectIdentifier(host)),
                "hosting_view": String(describing: ObjectIdentifier(host.view)),
                "width": String(describing: window.bounds.width), "height": String(describing: window.bounds.height),
                "key": String(window.isKeyWindow), "visible": String(!window.isHidden),
            ]
            releasedWindow = window
            releasedController = host
            releasedHostingView = host.view
            installed = true
        }

        func relinquishDestroyedReferences() {
            // Qualifying measurement: release fixture ownership without causing a second detach.
            if let window, var delegate = scene?.delegate as? UIWindowSceneDelegate,
                (delegate.window ?? nil) === window {
                delegate.window = nil
            }
            originalRoot = nil
            controller = nil
            window = nil
        }

        func cleanupAfterFailure() {
            // Only failure cleanup may actively detach, after partial observations are preserved.
            let ownedWindow = window ?? releasedWindow
            ownedWindow?.isHidden = true
            ownedWindow?.rootViewController = nil
            ownedWindow?.windowScene = nil
            relinquishDestroyedReferences()
        }

        func release(destroyed: Bool) {
            if destroyed {
                cleanupAfterFailure()
                return
            }
            window?.rootViewController = originalRoot
            originalRoot = nil
            controller = nil
            window = nil
        }
    }

    @MainActor
    private final class SceneHostLifetimeCallback {
        weak var holder: RUMSwiftUIViewTrackingEpoch?
        weak var session: RUMSwiftUIViewTrackingEpoch.Session?
        private var operation: (() -> Void)?
        private var admission: RUMSwiftUIViewCallbackAdmission?
        private let scene: RUMSceneIdentifier
        private(set) var calls = 0

        var admitsOriginalScene: Bool { admission?.admits(sceneIdentifier: scene) == true }

        init(binding: RUMSwiftUIViewFoundationBinding, scene: RUMSceneIdentifier) throws {
            let holder = RUMSwiftUIViewTrackingEpoch()
            let callback = try XCTUnwrap(holder.enter(binding))
            let admission = try XCTUnwrap(RUMSwiftUIViewCallbackAdmission(holder: holder, callback: callback))
            _ = admission.withSession {
                _ = $0.trackingState.update(attachment: .attached(scene))
                _ = $0.trackingState.appear()
            }
            self.holder = holder
            self.admission = admission
            self.scene = scene
            session = admission.withSession { $0 }
            operation = admission.disappearanceCallback { [weak self] in
                guard admission.admits(sceneIdentifier: scene) else {
                    return
                }
                _ = admission.withSession { _ in self?.calls += 1 }
            }
        }

        func invoke() { operation?() }
        func release() {
            operation = nil
            admission = nil
        }
    }

    @MainActor
    private final class SceneHostLifetimeNotifications {
        private var tokens: [NSObjectProtocol] = []
        private(set) var records: [[String: String]] = []
        private(set) var requestErrors: [[String: String]] = []
        private(set) var createdSceneIdentifiers: Set<String> = []

        func recordCreatedScene(_ identifier: String) {
            createdSceneIdentifiers.insert(identifier)
        }

        init() {
            for name in [UIScene.willConnectNotification, UIScene.didDisconnectNotification] {
                tokens.append(
                    NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                        MainActor.assumeIsolated {
                            guard let scene = notification.object as? UIScene else {
                                return
                            }
                            self?.records.append([
                                "notification": name.rawValue,
                                "scene": scene.session.persistentIdentifier,
                            ])
                        }
                    }
                )
            }
        }

        func recordRequestError(_ error: Error) {
            let error = error as NSError
            requestErrors.append(["domain": error.domain, "code": String(error.code)])
        }

        func contains(_ name: Notification.Name, scene: String) -> Bool {
            records.contains { $0["notification"] == name.rawValue && $0["scene"] == scene }
        }

        func stop() {
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens.removeAll()
        }
    }

    private final class SceneHostLifetimeRows: @unchecked Sendable {
        private let lock = NSLock()
        private var viewValues: [RUMViewEvent] = []
        private var resourceValues: [RUMResourceEvent] = []
        private var actionValues: [RUMActionEvent] = []

        func append(_ value: RUMViewEvent) {
            lock.lock()
            defer { lock.unlock() }
            viewValues.append(value)
        }
        func append(_ value: RUMResourceEvent) {
            lock.lock()
            defer { lock.unlock() }
            resourceValues.append(value)
        }
        func append(_ value: RUMActionEvent) {
            lock.lock()
            defer { lock.unlock() }
            actionValues.append(value)
        }
        var views: [RUMViewEvent] {
            lock.lock()
            defer { lock.unlock() }
            return viewValues
        }
        var resources: [RUMResourceEvent] {
            lock.lock()
            defer { lock.unlock() }
            return resourceValues
        }
        var actions: [RUMActionEvent] {
            lock.lock()
            defer { lock.unlock() }
            return actionValues
        }
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
