/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore
@testable import DatadogRUM

class RUMSessionTrackingTests: RUMSessionTestsBase {
    private func enableRUM(_ launchType: AppRunner.ProcessLaunchType, rumSetup: AppRunner.RUMSetup? = nil) -> AppRun {
        return .given(.appLaunch(type: launchType))
            .and(.enableRUM(after: timeToSDKInit, rumSetup: rumSetup))
    }

    private let dt: TimeInterval = 1

    // MARK: - User Launch → track user session

    /// User launch in `UISceneDelegate`-based app.
    private var userLaunchWithSceneDelegate: AppRunner.ProcessLaunchType { .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate) }
    /// User launch in `UIApplicationDelegate`-based app.
    private var userLaunchWithAppDelegate: AppRunner.ProcessLaunchType { .userLaunchInAppDelegateBasedApp(processLaunchDate: processLaunchDate) }

    #if !os(watchOS)
    private func simulateUserSession(in run: AppRun) -> AppRun {
        // Track app launch events within "ApplicationLaunch" view:
        var run = run
            .when(.trackTwoActions(after1: dt, after2: dt))
            .and(.trackTwoLongTasks(after1: dt, after2: dt))

        // Move to foreground, start "FirstView" and track events:
        run = run
            .and(.appBecomesActive(after: timeToAppBecomeActive))
            .and(.appDisplaysFirstFrame())
            .and(.startAutomaticView(after: 0, viewController: createMockView(viewControllerClassName: "FirstView")))
            .and(.trackResource(after: dt, duration: dt))
            .and(.trackTwoLongTasks(after1: dt, after2: dt))

        // Switch to "SecondView" and track events:
        run = run
            .and(.startAutomaticView(after: 0, viewController: createMockView(viewControllerClassName: "SecondView")))
            .and(.trackTwoActions(after1: dt, after2: dt))
            .and(.startResource(after: dt, key: "foreground-resource", url: .mockAny()))

        // Move to background, and track events:
        run = run
            .and(.appEntersBackground(after: dt))
            .and(.stopResource(after: dt, key: "foreground-resource"))
            .and(.trackTwoLongTasks(after1: dt, after2: dt))
            .and(.startResource(after: dt, key: "background-resource", url: .mockAny()))

        // Move to back foreground ("SecondView"), and track events:
        run = run
            .and(.appBecomesActive(after: dt))
            .and(.stopResource(after: dt, key: "background-resource"))
            .and(.trackTwoLongTasks(after1: dt, after2: dt))
            .and(.trackTwoActions(after1: dt, after2: dt))

        return run
    }

    private func assertUserSession(
        session: RUMSessionMatcher,
        expectBackgroundView: Bool
    ) {
        XCTAssertNotNil(session.ttidEvent)
        DDAssertEqual(session.timeToInitialDisplay, timeToSDKInit + 4 + timeToAppBecomeActive, accuracy: accuracy)
        DDAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
        DDAssertEqual(session.duration, timeToSDKInit + 4 * dt + timeToAppBecomeActive + 18 * dt, accuracy: accuracy)
        XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)

        var views = session.views
        var nextView = views.removeFirst()
        XCTAssertEqual(nextView.name, applicationLaunchViewName)
        DDAssertEqual(nextView.duration, timeToSDKInit + 4 * dt + timeToAppBecomeActive, accuracy: accuracy)
        XCTAssertEqual(nextView.actionEvents.count, 2)
        XCTAssertEqual(nextView.resourceEvents.count, 0)
        XCTAssertEqual(nextView.longTaskEvents.count, 2)

        nextView = views.removeFirst()
        XCTAssertEqual(nextView.name, "FirstView")
        DDAssertEqual(nextView.duration, 4 * dt, accuracy: accuracy)
        XCTAssertEqual(nextView.actionEvents.count, 0)
        XCTAssertEqual(nextView.resourceEvents.count, 1)
        XCTAssertEqual(nextView.longTaskEvents.count, 2)

        nextView = views.removeFirst()
        XCTAssertEqual(nextView.name, "SecondView")
        DDAssertEqual(nextView.duration, 5 * dt, accuracy: accuracy)
        XCTAssertEqual(nextView.actionEvents.count, 2)
        XCTAssertEqual(nextView.resourceEvents.count, 1)
        XCTAssertEqual(nextView.longTaskEvents.count, 0)

        if expectBackgroundView {
            nextView = views.removeFirst()
            XCTAssertEqual(nextView.name, backgroundViewName)
            DDAssertEqual(nextView.duration, 2 * dt, accuracy: accuracy)
            XCTAssertEqual(nextView.actionEvents.count, 0)
            XCTAssertEqual(nextView.resourceEvents.count, 1)
            XCTAssertEqual(nextView.longTaskEvents.count, 0)
        }

        nextView = views.removeFirst()
        XCTAssertEqual(nextView.name, "SecondView")
        DDAssertEqual(nextView.duration, 5 * dt, accuracy: accuracy)
        XCTAssertEqual(nextView.actionEvents.count, 2)
        XCTAssertEqual(nextView.resourceEvents.count, 0)
        XCTAssertEqual(nextView.longTaskEvents.count, 2)

        XCTAssertTrue(views.isEmpty)
    }
    #endif

    func testGivenUserLaunch_whenTrackingUserSession() throws {
        #if os(watchOS)
        throw XCTSkip("UIKit view instrumentation is not available on watchOS")
        #else
        // Given
        // - BET disabled
        let givens = [
            enableRUM(userLaunchWithSceneDelegate) { $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate() },
            enableRUM(userLaunchWithAppDelegate) { $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate() },
            enableRUM(userLaunchWithSceneDelegate) {
                $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
                $0.trackBackgroundEvents = true
            },
            enableRUM(userLaunchWithAppDelegate) {
                $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
                $0.trackBackgroundEvents = true
            },
        ]

        for given in givens {
            // When
            let when = simulateUserSession(in: given)

            // Then
            let session = try when.then().takeSingle()
            assertUserSession(
                session: session,
                expectBackgroundView: given == givens[2] || given == givens[3]
            )
        }
        #endif
    }

    // MARK: - Prewarming & Background Launch → track background session

    private func simulateBackgroundSession(in run: AppRun) -> AppRun {
        // Track background events:
        var run = run
            .when(.trackResource(after: dt, duration: dt))
            .and(.trackTwoActions(after1: dt, after2: dt))
            .and(.trackTwoLongTasks(after1: dt, after2: dt))

        // Await tvOS launch window duration:
        run = run
            .and(.init { $0.advanceTime(by: LaunchReasonResolver.Constants.launchWindowThreshold) })

        // Track more background events:
        run = run
            .and(.trackResource(after: dt, duration: dt))
            .and(.trackTwoActions(after1: dt, after2: dt))
            .and(.trackTwoLongTasks(after1: dt, after2: dt))

        return run
    }

    private func assertBackgroundSession(
        session: RUMSessionMatcher,
        expectedSessionPrecondition: RUMSessionPrecondition
    ) {
        XCTAssertNil(session.ttidEvent)
        XCTAssertNil(session.timeToInitialDisplay)
        DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + dt, accuracy: accuracy)
        DDAssertEqual(session.duration, 5 * dt + LaunchReasonResolver.Constants.launchWindowThreshold + 6 * dt, accuracy: accuracy)
        XCTAssertEqual(session.sessionPrecondition, expectedSessionPrecondition)
        XCTAssertEqual(session.views.count, 1)

        let view = session.views[0]
        XCTAssertEqual(view.name, backgroundViewName)
        DDAssertEqual(view.duration, 5 * dt + LaunchReasonResolver.Constants.launchWindowThreshold + 6 * dt, accuracy: accuracy)
        XCTAssertEqual(view.actionEvents.count, 4)
        XCTAssertEqual(view.resourceEvents.count, 2)
        XCTAssertEqual(view.longTaskEvents.count, 4)
    }

    @available(tvOS, unavailable)
    private var osPrewarmLaunch: AppRunner.ProcessLaunchType { .osPrewarm(processLaunchDate: processLaunchDate, runtimeLoadDate: runtimeLoadDate) }

    func testGivenPrewarmedLaunch_whenTrackingBackgroundSession() throws {
        #if os(tvOS) || os(watchOS)
        throw XCTSkip("This test is not available on tvOS nor watchOS")
        #else
        // Given
        // - BET disabled
        let given = enableRUM(osPrewarmLaunch)

        // When
        let when = simulateBackgroundSession(in: given)

        // Then
        let sessions = try when.then()
        XCTAssertTrue(sessions.isEmpty)
        #endif
    }

    func testGivenPrewarmedLaunch_andBETEnabled_whenTrackingBackgroundSession() throws {
        #if os(tvOS) || os(watchOS)
        throw XCTSkip("This test is not available on tvOS nor watchOS")
        #else
        // Given
        // - BET enabled
        let given = enableRUM(osPrewarmLaunch) { $0.trackBackgroundEvents = true }

        let when = simulateBackgroundSession(in: given)

        let session = try when.then().takeSingle()
        assertBackgroundSession(session: session, expectedSessionPrecondition: .prewarm)
        #endif
    }

    private var backgroundLaunch: AppRunner.ProcessLaunchType { .backgroundLaunch(processLaunchDate: processLaunchDate) }

    func testGivenBackgroundLaunch_whenTrackingBackgroundSession() throws {
        // Given
        // - BET disabled
        let given = enableRUM(backgroundLaunch)

        // When
        let when = simulateBackgroundSession(in: given)

        // Then
        let sessions = try when.then()
        XCTAssertTrue(sessions.isEmpty)
    }

    func testGivenBackgroundLaunch_andBETEnabled_whenTrackingBackgroundSession() throws {
        // Given
        // - BET enabled
        let given = enableRUM(backgroundLaunch) { $0.trackBackgroundEvents = true }

        // When
        let when = simulateBackgroundSession(in: given)

        // Then
        let session = try when.then().takeSingle()
        assertBackgroundSession(session: session, expectedSessionPrecondition: .backgroundLaunch)
    }

    // MARK: - Prewarming & Background Launch → suspend → resume by user session

    private func simulateSuspendedBackgroundSessionResumedByUser(in run: AppRun) -> AppRun {
        // Track background events:
        var run = run
            .when(.trackResource(after: dt, duration: dt))
            .and(.trackTwoActions(after1: dt, after2: dt))
            .and(.init { $0.advanceTime(by: LaunchReasonResolver.Constants.launchWindowThreshold) })
            .and(.trackResource(after: dt, duration: dt))

        // Suspend for long time
        run = run
            .and(.advanceTime(by: 2.hours))

        // Move to foreground, start "FirstView" and track events:
        run = run
            .and(.appBecomesActive(after: 0))
        #if os(watchOS)
        run = run.and(.startManualView(after: 0, viewName: "FirstView", viewKey: "FirstView"))
        #else
        run = run.and(.startAutomaticView(after: 0, viewController: createMockView(viewControllerClassName: "FirstView")))
        #endif
        run = run
            .and(.trackResource(after: dt, duration: dt))
            .and(.trackTwoLongTasks(after1: dt, after2: dt))

        return run
    }

    private func assertSuspendedBackgroundSession(
        session: RUMSessionMatcher,
        expectedSessionPrecondition: RUMSessionPrecondition
    ) {
        XCTAssertNil(session.ttidEvent)
        XCTAssertNil(session.timeToInitialDisplay)
        DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + dt, accuracy: accuracy)
        DDAssertEqual(session.duration, 3 * dt + LaunchReasonResolver.Constants.launchWindowThreshold + 2 * dt, accuracy: accuracy)
        XCTAssertEqual(session.sessionPrecondition, expectedSessionPrecondition)
        XCTAssertEqual(session.views.count, 1)

        let view = session.views[0]
        XCTAssertEqual(view.name, backgroundViewName)
        DDAssertEqual(view.duration, 3 * dt + LaunchReasonResolver.Constants.launchWindowThreshold + 2 * dt, accuracy: accuracy)
        XCTAssertEqual(view.actionEvents.count, 2)
        XCTAssertEqual(view.resourceEvents.count, 2)
        XCTAssertEqual(view.longTaskEvents.count, 0)
    }

    private func assertResumedUserSession(
        session: RUMSessionMatcher,
        expectedSessionPrecondition: RUMSessionPrecondition
    ) {
        XCTAssertNil(session.ttidEvent)
        XCTAssertNil(session.timeToInitialDisplay)
        DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + 6 * dt + LaunchReasonResolver.Constants.launchWindowThreshold + 2.hours, accuracy: accuracy)
        DDAssertEqual(session.duration, 4 * dt, accuracy: accuracy)
        XCTAssertEqual(session.sessionPrecondition, expectedSessionPrecondition)
        XCTAssertEqual(session.views.count, 1)

        let view = session.views[0]
        XCTAssertEqual(view.name, "FirstView")
        DDAssertEqual(view.duration, 4 * dt, accuracy: accuracy)
        XCTAssertEqual(view.actionEvents.count, 0)
        XCTAssertEqual(view.resourceEvents.count, 1)
        XCTAssertEqual(view.longTaskEvents.count, 2)
    }

    func testGivenPrewarmedLaunch_andSuspendedBackgroundSession_whenItGetsResumedByUserSession() throws {
        #if os(tvOS) || os(watchOS)
        throw XCTSkip("This test is not available on tvOS or watchOS")
        #else
        // Given
        // - BET disabled
        let given = enableRUM(osPrewarmLaunch) { $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate() }

        // When
        let when = simulateSuspendedBackgroundSessionResumedByUser(in: given)

        // Then
        let userSession = try when.then().takeSingle()
        assertResumedUserSession(session: userSession, expectedSessionPrecondition: .inactivityTimeout)
        #endif
    }

    func testGivenPrewarmedLaunch_andBETEnabled_andSuspendedBackgroundSession_whenItGetsResumedByUserSession() throws {
        #if os(tvOS) || os(watchOS)
        throw XCTSkip("This test is not available on tvOS or watchOS")
        #else
        // Given
        // - BET enabled
        let given = enableRUM(osPrewarmLaunch) {
            $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
            $0.trackBackgroundEvents = true
        }

        // When
        let when = simulateSuspendedBackgroundSessionResumedByUser(in: given)

        // Then
        let (backgroundSession, userSession) = try when.then().takeTwo()
        assertSuspendedBackgroundSession(session: backgroundSession, expectedSessionPrecondition: .prewarm)
        assertResumedUserSession(session: userSession, expectedSessionPrecondition: .inactivityTimeout)
        #endif
    }

    func testGivenBackgroundLaunch_andSuspendedBackgroundSession_whenItGetsResumedByUserSession() throws {
        // Given
        // - BET disabled
        // On watchOS, UIKit view instrumentation is not available — use plain RUM config.
        #if os(watchOS)
        let given = enableRUM(backgroundLaunch)
        #else
        let given = enableRUM(backgroundLaunch) { $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate() }
        #endif

        // When
        let when = simulateSuspendedBackgroundSessionResumedByUser(in: given)

        // Then
        let userSession = try when.then().takeSingle()
        assertResumedUserSession(session: userSession, expectedSessionPrecondition: .inactivityTimeout)
    }

    func testGivenBackgroundLaunch_andBETEnabled_andSuspendedBackgroundSession_whenItGetsResumedByUserSession() throws {
        // Given
        // - BET enabled
        // On watchOS, UIKit view instrumentation is not available — use plain RUM config.
        #if os(watchOS)
        let given = enableRUM(backgroundLaunch) { $0.trackBackgroundEvents = true }
        #else
        let given = enableRUM(backgroundLaunch) {
            $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
            $0.trackBackgroundEvents = true
        }
        #endif

        // When
        let when = simulateSuspendedBackgroundSessionResumedByUser(in: given)

        // Then
        let (backgroundSession, userSession) = try when.then().takeTwo()
        assertSuspendedBackgroundSession(session: backgroundSession, expectedSessionPrecondition: .backgroundLaunch)
        assertResumedUserSession(session: userSession, expectedSessionPrecondition: .inactivityTimeout)
    }
}

#if os(iOS)
import SwiftUI
import UIKit

@MainActor
final class RUMViewLifetimeIntegrationTests: XCTestCase {
    private enum TrackingMode: String {
        case uiKit
        case automaticSwiftUI
        case manualSwiftUI
    }

    func testAutomaticUIKitControllerReleasesWhileResourceOwnerRemains() async throws {
        try await assertHostLifetime(mode: .uiKit)
    }

    func testAutomaticSwiftUIHostReleasesWhileResourceOwnerRemains() async throws {
        try await assertHostLifetime(mode: .automaticSwiftUI)
    }

    func testManualSwiftUIHostReleasesWhileResourceOwnerRemains() async throws {
        try await assertHostLifetime(mode: .manualSwiftUI)
    }

    private func assertHostLifetime(mode: TrackingMode) async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("rum-host-lifetime-\(UUID().uuidString)", isDirectory: true)
        let coreURL = fixtureRoot.appendingPathComponent("core", isDirectory: true)
        try FileManager.default.createDirectory(at: coreURL, withIntermediateDirectories: true)
        defer { XCTAssertNoThrow(try FileManager.default.removeItem(at: fixtureRoot)) }
        let coreDirectory = CoreDirectory(osDirectory: Directory(url: fixtureRoot), coreDirectory: Directory(url: coreURL))
        let context = DatadogContext.mockWith(applicationStateHistory: .mockAppInForeground())
        let sdkCore = DatadogCore(
            directory: coreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: context.trackingConsent,
            performance: .mockAny(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: DatadogContextProvider(context: context),
            applicationVersion: context.version,
            maxBatchesPerUpload: 1,
            backgroundTasksEnabled: false
        )
        let core = DatadogCoreProxy(core: sdkCore)
        let configurationDelivered = expectation(description: "Pending core configuration delivered before fixture cleanup")
        sdkCore.bus.connect(
            FeatureMessageReceiverMock { message in
                guard case .telemetry(.configuration) = message else {
                    return
                }
                configurationDelivered.fulfill()
            },
            forKey: "view-lifetime-configuration"
        )
        let originalKeyWindow = UIApplication.shared.windows.first(where: { $0.isKeyWindow })
        let window = originalKeyWindow?.windowScene.map { UIWindow(windowScene: $0) }
            ?? UIWindow(frame: UIScreen.main.bounds)
        window.frame = UIScreen.main.bounds
        defer {
            // These operations occur after the critical host/view ownership assertions.
            window.rootViewController = nil
            window.isHidden = true
            XCTAssertNoThrow(try core.flushAndTearDown())
            originalKeyWindow?.makeKey()
        }

        var configuration = RUM.Configuration(applicationID: "00000000-0000-0000-0000-000000000213")
        configuration.longTaskThreshold = nil
        configuration.appHangThreshold = nil
        configuration.trackWatchdogTerminations = false
        configuration.vitalsUpdateFrequency = nil
        configuration.collectAccessibility = false
        configuration.telemetrySampleRate = 0
        switch mode {
        case .uiKit:
            configuration.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
        case .automaticSwiftUI:
            configuration.swiftUIViewsPredicate = DefaultSwiftUIRUMViewsPredicate()
        case .manualSwiftUI:
            break
        }
        RUM.enable(with: configuration, in: core)
        var observationError: Error?
        do {
            let monitor = try XCTUnwrap(core.feature(named: RUMFeature.name, type: RUMFeature.self)?.monitor)
            var priorViewIDs: [String] = []

            for cycle in 0..<2 {
                let lifecycle = RUMViewLifetimeLifecycle()
                var controller: UIViewController?
                weak var observedController: UIViewController?
                weak var observedContent: RUMViewLifetimeContentWitness?
                autoreleasepool {
                    let witness = RUMViewLifetimeContentWitness()
                    observedContent = witness
                    switch mode {
                    case .uiKit:
                        let viewController = RUMViewLifetimeViewController(lifecycle: lifecycle)
                        viewController.contentWitness = witness
                        controller = viewController
                    case .automaticSwiftUI:
                        controller = UIHostingController(
                            rootView: RUMViewLifetimeContent(witness: witness)
                                .onAppear { lifecycle.appeared += 1 }
                                .onDisappear { lifecycle.disappeared += 1 }
                        )
                    case .manualSwiftUI:
                        controller = UIHostingController(
                            rootView: RUMViewLifetimeContent(witness: witness)
                                .trackRUMView(name: "ManualLifetime", in: core)
                                .onAppear { lifecycle.appeared += 1 }
                                .onDisappear { lifecycle.disappeared += 1 }
                        )
                    }
                    observedController = controller
                }
                XCTAssertNotNil(observedController)
                XCTAssertNotNil(observedContent)
                let controllerIdentity = try XCTUnwrap(controller.map(ViewIdentifier.init))
                window.rootViewController = controller
                window.makeKeyAndVisible()

                weak var observedView: RUMViewScope?
                let appeared = await observe(timeout: 5) {
                    core.flush()
                    observedView = monitor.applicationScope.sessionScopes.last?.viewScopes.last(where: { $0.isActiveView })
                    let matches = mode == .manualSwiftUI
                        ? observedView?.viewName == "ManualLifetime"
                        : observedView?.identity == controllerIdentity
                    return matches && observedView?.isActiveView == true && lifecycle.appeared == 1 && controller?.view.window === window
                }
                XCTAssertTrue(appeared, "A real appearance and exact active RUM owner are required")
                let viewID = try XCTUnwrap(observedView?.viewUUID.toRUMDataFormat)
                XCTAssertFalse(priorViewIDs.contains(viewID))
                priorViewIDs.append(viewID)
                let resourceKey = "host-lifetime-\(mode.rawValue)-\(cycle)"
                let url = "https://example.com/\(resourceKey)"
                monitor.startResource(resourceKey: resourceKey, httpMethod: .get, urlString: url, attributes: [:])
                core.flush()
                weak var observedResource = observedView?.resourceScopes[resourceKey]
                XCTAssertNotNil(observedResource)
                XCTAssertNotNil(observedView)

                autoreleasepool {
                    window.rootViewController = nil
                    window.isHidden = true
                    controller = nil
                }
                let hostReleased = await observe(timeout: 2) {
                    core.flush()
                    return lifecycle.disappeared == 1 && observedController == nil && observedContent == nil && observedView?.isActiveView == false
                }
                XCTAssertTrue(hostReleased)
                XCTAssertNil(observedController, "The SDK must not retain a removed native controller or hosting controller")
                XCTAssertNil(observedContent, "The removed SwiftUI content or UIKit payload must release while RUM remains enabled")
                XCTAssertNotNil(observedView, "Pending work still legitimately owns its stopped RUM view")
                XCTAssertNotNil(observedResource)
                XCTAssertEqual(observedView?.viewUUID.toRUMDataFormat, viewID)
                XCTAssertFalse(observedView?.isActiveView ?? true)

                // A command after the peer starts replaces the legitimate restoration owner.
                let peerKey = "lifetime-peer-\(mode.rawValue)-\(cycle)"
                monitor.startView(key: peerKey, name: "LifetimePeer", attributes: [:])
                core.flush()
                weak var peer = monitor.applicationScope.activeSession?.viewScopes.first(where: { $0.isActiveView })
                let peerID = try XCTUnwrap(peer?.viewUUID.toRUMDataFormat)
                XCTAssertEqual(peer?.viewName, "LifetimePeer")
                XCTAssertNotEqual(peerID, viewID)
                monitor.addViewAttribute(forKey: "lifetime.peer", value: peerKey)
                core.flush()
                XCTAssertTrue(peer?.isActiveView == true)
                XCTAssertNotNil(observedView)
                XCTAssertNotNil(observedResource)

                let pendingBeforeCompletion = observedView != nil && observedResource != nil && observedView?.isActiveView == false
                let completedAt = ProcessInfo.processInfo.systemUptime
                monitor.stopResource(resourceKey: resourceKey, statusCode: 200, kind: .native, size: 1, attributes: [:])
                core.flush()
                let releaseBudget = max(0, 2 - (ProcessInfo.processInfo.systemUptime - completedAt))
                let ownersReleased = await observe(timeout: releaseBudget) {
                    core.flush()
                    return observedView == nil && observedResource == nil
                }
                let events = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMResourceEvent.self, timeout: .now() + 2)
                let matching = events.filter { $0.resource.url == url }
                XCTAssertEqual(matching.count, 1)
                XCTAssertEqual(matching.first?.view.id, viewID)
                XCTAssertTrue(ownersReleased)
                XCTAssertNil(observedView)
                XCTAssertNil(observedResource)
                XCTAssertNotNil(core.feature(named: RUMFeature.name, type: RUMFeature.self), "Owner release must precede SDK teardown")
                XCTAssertTrue(peer?.isActiveView == true)
                XCTAssertEqual(peer?.viewUUID.toRUMDataFormat, peerID)
                let row: [String: Any] = [
                    "mode": mode.rawValue, "cycle": cycle,
                    "appeared": lifecycle.appeared, "disappeared": lifecycle.disappeared,
                    "host_released_within_two_seconds": hostReleased,
                    "controller_alive": observedController != nil, "content_alive": observedContent != nil,
                    "resource_view_id": viewID, "peer_view_id": peerID,
                    "resource_event_count": matching.count, "event_view_id": matching.first?.view.id ?? "missing",
                    "pending_before_completion": pendingBeforeCompletion,
                    "owners_released_within_two_seconds": ownersReleased,
                    "view_alive": observedView != nil, "resource_alive": observedResource != nil,
                    "peer_active": peer?.isActiveView == true,
                    "peer_unchanged": peer?.viewUUID.toRUMDataFormat == peerID,
                    "sdk_feature_present": core.feature(named: RUMFeature.name, type: RUMFeature.self) != nil
                ]
                let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
                print("EXP215_NATIVE_LIFETIME \(String(decoding: data, as: UTF8.self))")
                monitor.stopView(key: peerKey, attributes: [:])
                core.flush()
            }
        } catch {
            observationError = error
        }
        await dd_fulfillment(for: [configurationDelivered], timeout: 7)
        if let observationError = observationError {
            throw observationError
        }
    }

    private func observe(timeout: TimeInterval, _ predicate: @escaping () -> Bool) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if predicate() {
                return true
            }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(min(0.01, remaining) * 1_000_000_000))
            }
        }
        return false
    }
}

private final class RUMViewLifetimeContentWitness {}

private final class RUMViewLifetimeLifecycle {
    var appeared = 0
    var disappeared = 0
}

private final class RUMViewLifetimeViewController: UIViewController {
    let lifecycle: RUMViewLifetimeLifecycle
    var contentWitness: RUMViewLifetimeContentWitness?

    init(lifecycle: RUMViewLifetimeLifecycle) {
        self.lifecycle = lifecycle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        lifecycle = RUMViewLifetimeLifecycle()
        super.init(coder: coder)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        lifecycle.appeared += 1
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        lifecycle.disappeared += 1
    }
}

private struct RUMViewLifetimeContent: SwiftUI.View {
    let witness: RUMViewLifetimeContentWitness

    var body: some SwiftUI.View {
        Text("View lifetime")
            .onAppear { withExtendedLifetime(witness) {} }
    }
}
#endif
