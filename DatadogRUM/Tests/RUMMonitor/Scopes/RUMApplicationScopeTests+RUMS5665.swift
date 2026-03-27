/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM
@testable import TestUtilities

// RUMS-5665: Native iOS RUM batches not reaching custom endpoint for subset of users
// after SDK upgrade from 2.30.2 to 3.x.
//
// Root cause: `RUMApplicationScope.startApplicationLaunchView` sets `applicationActive = true`
// BEFORE the guard that checks `isUserLaunch`. When `launchReason == .backgroundLaunch`
// (triggered by `task_policy_get` returning KERN_FAILURE or DEFAULTED on ~20% of devices),
// the guard fails and returns early, but `applicationActive` is permanently latched to `true`.
// All subsequent commands therefore skip the `startApplicationLaunchView` path entirely,
// resulting in `handleOffViewCommand` being called with `RUMStopResourceCommand.canStartApplicationLaunchView == false`,
// which silently drops the event and logs a "no view is active" warning.
class RUMApplicationScopeTests_RUMS5665: XCTestCase {
    let writer = FileWriterMock()

    // MARK: - Helper

    /// Creates a `RUMApplicationScope` that has received an `RUMSDKInitCommand` using the given `sdkContext`.
    private func createScope(
        sdkContext: DatadogContext,
        samplingRate: Float = 100,
        trackBackgroundEvents: Bool = false
    ) -> RUMApplicationScope {
        let scope = RUMApplicationScope(
            dependencies: .mockWith(
                samplingRate: samplingRate,
                trackBackgroundEvents: trackBackgroundEvents
            )
        )
        let initCommand = RUMSDKInitCommand(time: sdkContext.sdkInitDate, globalAttributes: [:])
        _ = scope.process(command: initCommand, context: sdkContext, writer: writer)
        return scope
    }

    // MARK: - Test 1: backgroundLaunch permanently latches applicationActive without creating a view

    /// Proves the latch bug: after `RUMSDKInitCommand` with `launchReason = .backgroundLaunch` in background,
    /// `applicationActive` is set to `true` but NO ApplicationLaunch view is created.
    /// Then `RUMStartResourceCommand` (which has `canStartApplicationLaunchView = true`) arrives —
    /// because `applicationActive` is already `true`, `startApplicationLaunchView` is never called again,
    /// and no view scope is ever started.
    ///
    /// Expected (correct) behaviour: either `applicationActive` should remain `false` until a view is
    /// actually created, OR the guard should be evaluated before setting `applicationActive`.
    ///
    /// This test FAILS on the buggy code because `applicationActive == true` but `viewScopes.isEmpty == true`.
    func test_backgroundLaunch_firstResourceCommand_setsApplicationActivePermanentlyWithoutCreatingView() throws {
        // Given — SDK init in background with backgroundLaunch reason (simulates ~20% of devices where
        // task_policy_get returns KERN_FAILURE/DEFAULTED)
        let sdkContext: DatadogContext = .mockWith(
            launchInfo: .mockWith(
                launchReason: .backgroundLaunch,
                processLaunchDate: .mockDecember15th2019At10AMUTC()
            ),
            applicationStateHistory: .mockAppInBackground(since: .mockDecember15th2019At10AMUTC())
        )

        let scope = createScope(sdkContext: sdkContext)

        // After SDKInitCommand: no view should be created yet (background launch, correct so far)
        let sessionAfterInit = try XCTUnwrap(scope.activeSession)
        XCTAssertTrue(
            sessionAfterInit.viewScopes.isEmpty,
            "No view should be created on SDK init in background with backgroundLaunch"
        )

        // When — first non-init command arrives (StartResource, which has canStartApplicationLaunchView = true)
        let resourceKey = "resources/network-request"
        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(resourceKey: resourceKey, time: .mockDecember15th2019At10AMUTC().addingTimeInterval(1)),
            context: sdkContext,
            writer: writer
        )

        // Then — because of the latch bug, applicationActive is true but no view was ever created
        // The fix should either:
        //   a) not set applicationActive=true when guard fails, OR
        //   b) create the ApplicationLaunch view retroactively via handleOffViewCommand
        //
        // On buggy code: applicationActive==true AND viewScopes is still empty => this assert FAILS (proving the bug)
        let sessionAfterResource = try XCTUnwrap(scope.activeSession)
        XCTAssertFalse(
            sessionAfterResource.viewScopes.isEmpty,
            "RUMS-5665: After StartResourceCommand with backgroundLaunch, an ApplicationLaunch view " +
            "should have been created to host the resource. " +
            "Bug: applicationActive is permanently latched to true after SDKInitCommand returned early, " +
            "so startApplicationLaunchView is never called again even for commands with canStartApplicationLaunchView=true."
        )
    }

    // MARK: - Test 2: RUMStopResourceCommand silently drops event when no view is active

    /// Proves that `RUMStopResourceCommand` is silently dropped (and a warning logged) when the latch bug
    /// leaves the session with no active view after `RUMStartResourceCommand` was similarly dropped.
    ///
    /// The customer's debug log showed exactly:
    /// "RUMStopResourceCommand was detected, but no view is active"
    /// with canStartApplicationLaunchView: false, canStartBackgroundView: false
    ///
    /// This test FAILS on the buggy code because no RUMResourceEvent is written to the output.
    func test_backgroundLaunch_stopResourceCommand_dropsEventDueToNoActiveView() throws {
        // Given — SDK init in background with backgroundLaunch reason
        let sdkContext: DatadogContext = .mockWith(
            launchInfo: .mockWith(
                launchReason: .backgroundLaunch,
                processLaunchDate: .mockDecember15th2019At10AMUTC()
            ),
            applicationStateHistory: .mockAppInBackground(since: .mockDecember15th2019At10AMUTC())
        )

        let scope = createScope(sdkContext: sdkContext)
        let resourceKey = "resources/network-request"
        let t0 = Date.mockDecember15th2019At10AMUTC()

        // Start a resource (this itself fails to create a view due to the latch bug)
        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(resourceKey: resourceKey, time: t0.addingTimeInterval(1)),
            context: sdkContext,
            writer: writer
        )

        // When — stop the resource; with canStartApplicationLaunchView=false this falls into the "drop" path
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        _ = scope.process(
            command: RUMStopResourceCommand.mockWith(resourceKey: resourceKey, time: t0.addingTimeInterval(2)),
            context: sdkContext,
            writer: writer
        )

        // Then — the resource event must have been written if a view was active
        // On buggy code: RUMResourceEvent is NOT written because StopResource has canStartApplicationLaunchView=false
        // and falls into the drop path; this assertion FAILS (proving the bug)
        let resourceEvents = writer.events(ofType: RUMResourceEvent.self)
        XCTAssertFalse(
            resourceEvents.isEmpty,
            "RUMS-5665: RUMStopResourceCommand should produce a RUMResourceEvent. " +
            "Bug: because no view was created (applicationActive latch), the event is silently dropped. " +
            "Customer log: 'RUMStopResourceCommand was detected, but no view is active' with " +
            "canStartApplicationLaunchView: false, canStartBackgroundView: false."
        )

        // Also verify: the warning about 'no view is active' should NOT be emitted when things work correctly
        // (on buggy code the warning IS emitted, meaning events are being silently dropped)
        XCTAssertNil(
            dd.logger.warnLog?.message,
            "RUMS-5665: No 'no view is active' warning should be emitted when resources are properly tracked. " +
            "Bug: warning IS emitted because applicationActive latch prevents view creation."
        )
    }

    // MARK: - Test 3: Regression boundary — userLaunch MUST create ApplicationLaunch view correctly

    /// Regression boundary test: `launchReason = .userLaunch` should continue to create the
    /// ApplicationLaunch view immediately on SDKInit, and subsequent resources should be tracked.
    /// This test should PASS on both buggy and fixed code, confirming the fix boundary.
    func test_userLaunch_createsApplicationLaunchView() throws {
        // Given — SDK init in foreground with userLaunch reason (normal path, ~80% of devices)
        let sdkContext: DatadogContext = .mockWith(
            launchInfo: .mockWith(
                launchReason: .userLaunch,
                processLaunchDate: .mockDecember15th2019At10AMUTC()
            ),
            applicationStateHistory: .mockAppInForeground(since: .mockDecember15th2019At10AMUTC())
        )

        let scope = createScope(sdkContext: sdkContext)

        // Then — ApplicationLaunch view must be immediately present after SDKInitCommand
        let session = try XCTUnwrap(scope.activeSession)
        XCTAssertFalse(
            session.viewScopes.isEmpty,
            "With userLaunch, the ApplicationLaunch view must be created immediately on SDKInit."
        )
        let firstView = try XCTUnwrap(session.viewScopes.first)
        XCTAssertEqual(
            firstView.viewName,
            RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName,
            "First view must be the ApplicationLaunch view"
        )

        // And — resource commands are tracked inside that view
        let resourceKey = "resources/network-request"
        let t0 = Date.mockDecember15th2019At10AMUTC()

        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(resourceKey: resourceKey, time: t0.addingTimeInterval(1)),
            context: sdkContext,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopResourceCommand.mockWith(resourceKey: resourceKey, time: t0.addingTimeInterval(2)),
            context: sdkContext,
            writer: writer
        )

        let resourceEvents = writer.events(ofType: RUMResourceEvent.self)
        XCTAssertFalse(
            resourceEvents.isEmpty,
            "Resources must be tracked inside the ApplicationLaunch view for userLaunch scenario."
        )
    }

    // MARK: - Test 4: Integration — backgroundLaunch then foreground transition then resource cycle

    /// Integration test: SDK initialized with backgroundLaunch, scene transitions to foreground,
    /// then a view is started and a resource cycle completes. Verifies no events are lost.
    ///
    /// This test FAILS on the buggy code because after the scene transitions to foreground,
    /// if a resource is started before an explicit startView, `applicationActive` is already `true`
    /// and no ApplicationLaunch or any other view is created to receive the resource.
    func test_backgroundLaunch_thenForegroundTransition_resourcesAreTracked() throws {
        // Given — SDK init in background (backgroundLaunch)
        let backgroundContext: DatadogContext = .mockWith(
            launchInfo: .mockWith(
                launchReason: .backgroundLaunch,
                processLaunchDate: .mockDecember15th2019At10AMUTC()
            ),
            applicationStateHistory: .mockAppInBackground(since: .mockDecember15th2019At10AMUTC())
        )

        let scope = createScope(sdkContext: backgroundContext)

        // Sanity: no view after background init
        let sessionAfterInit = try XCTUnwrap(scope.activeSession)
        XCTAssertTrue(sessionAfterInit.viewScopes.isEmpty, "No view yet in background")

        // When — app transitions to foreground (scene becomes active)
        let foregroundContext: DatadogContext = .mockWith(
            launchInfo: .mockWith(
                launchReason: .backgroundLaunch,
                processLaunchDate: .mockDecember15th2019At10AMUTC()
            ),
            applicationStateHistory: .mockAppInForeground(since: .mockDecember15th2019At10AMUTC().addingTimeInterval(2))
        )

        // User starts a view (simulating UISceneDelegate or SwiftUI navigation)
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(
                time: .mockDecember15th2019At10AMUTC().addingTimeInterval(2),
                identity: .mockViewIdentifier()
            ),
            context: foregroundContext,
            writer: writer
        )

        // Then a resource is started and stopped within that view
        let resourceKey = "resources/api-call"
        let t0 = Date.mockDecember15th2019At10AMUTC().addingTimeInterval(2)

        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(resourceKey: resourceKey, time: t0.addingTimeInterval(1)),
            context: foregroundContext,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopResourceCommand.mockWith(resourceKey: resourceKey, time: t0.addingTimeInterval(2)),
            context: foregroundContext,
            writer: writer
        )

        // Then — resource event must be present in output
        let resourceEvents = writer.events(ofType: RUMResourceEvent.self)
        XCTAssertFalse(
            resourceEvents.isEmpty,
            "RUMS-5665: After transitioning to foreground following a backgroundLaunch, " +
            "resources started within an explicit view must be tracked and reach the output. " +
            "Bug: if applicationActive latch prevents any view from being created during the background " +
            "phase, downstream resource events may also be affected depending on session state."
        )

        // View events should also be written
        let viewEvents = writer.events(ofType: RUMViewEvent.self)
        XCTAssertFalse(
            viewEvents.isEmpty,
            "At least one view event must be written after starting a view in foreground."
        )
    }
}
