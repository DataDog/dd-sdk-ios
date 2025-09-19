/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import HTTPServerMock
import TestUtilities
import XCTest
import DatadogInternal

private extension ExampleApplication {
    func tapStartLoginFlow() {
        buttons["Start Login"].tap()
    }
    
    func tapSucceedLoginFlow() {
        buttons["Succeed Login"].tap()
    }
    
    func tapFailLoginFlow() {
        buttons["Fail Login"].tap()
    }

    func tapStartConcurrentOperations() {
        buttons["Start Photo"].tap()
    }
    
    func tapSucceedConcurrentOperations() {
        buttons["Succeed Photo"].tap()
    }
    
    func tapFailConcurrentOperations() {
        buttons["Fail Photo"].tap()
    }
    
    func tapPushNextScreen() {
        buttons["Push Next Screen"].tap()
    }

    func tapSucceedLoginOnNextView() {
        buttons["Succeed Login on Next View"].tap()
    }
}

class RUMFeatureOperationsScenarioTests: IntegrationTests, RUMCommonAsserts {

    // MARK: - Basic Operation Test

    func testBasicFeatureOperation() throws {
        let rumServerSession = server.obtainUniqueRecordingSession()
        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "RUMFeatureOperationsScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumServerSession.recordingURL
            )
        )

        let screen = ExampleApplication()

        // Test basic login flow (no operation key)
        screen.tapStartLoginFlow()
        screen.tapSucceedLoginFlow()

        try app.endRUMSession()

        let recordedRUMRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.singleSession(from: requests)?.hasEnded() ?? false
        }

        assertRUM(requests: recordedRUMRequests)
        let session = try XCTUnwrap(RUMSessionMatcher.singleSession(from: recordedRUMRequests))

        // Verify login flow vital events
        let vitalEvents = session.vitalEvents
        let loginStartEvents = vitalEvents.filter { $0.vital.name == "login_flow" && $0.vital.stepType == .start }
        let loginSucceedEvents = vitalEvents.filter { $0.vital.name == "login_flow" && $0.vital.stepType == .end && $0.vital.failureReason == nil }

        XCTAssertEqual(loginStartEvents.count, 1, "Should have one login flow start event")
        XCTAssertEqual(loginSucceedEvents.count, 1, "Should have one login flow succeed event")

        // Verify no operation key for basic operation
        for event in vitalEvents {
            XCTAssertNil(event.vital.operationKey, "Basic operation should not have operation key")
        }
    }

    // MARK: - Failure Scenarios Test

    func testFeatureOperationWithFailure() throws {
        let rumServerSession = server.obtainUniqueRecordingSession()
        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "RUMFeatureOperationsScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumServerSession.recordingURL
            )
        )

        let screen = ExampleApplication()

        // Test different failure scenarios
        screen.tapStartLoginFlow()
        screen.tapFailLoginFlow()

        try app.endRUMSession()

        let recordedRUMRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.singleSession(from: requests)?.hasEnded() ?? false
        }

        assertRUM(requests: recordedRUMRequests)
        let session = try XCTUnwrap(RUMSessionMatcher.singleSession(from: recordedRUMRequests))

        // Verify error vital events
        let vitalEvents = session.vitalEvents
        let loginStartEvents = vitalEvents.filter { $0.vital.name == "login_flow" && $0.vital.stepType == .start }
        let loginFailEvents = vitalEvents.filter { $0.vital.name == "login_flow" && $0.vital.stepType == .end && $0.vital.failureReason == .error }

        XCTAssertEqual(loginStartEvents.count, 1, "Should have one login flow start event")
        XCTAssertEqual(loginFailEvents.count, 1, "Should have one login flow fail event")

        // Verify failure reason
        let failEvent = try XCTUnwrap(loginFailEvents.first)
        XCTAssertEqual(failEvent.vital.failureReason, .error, "Should have correct failure reason")
    }

    // MARK: - Multiple Operation Instances Test

    func testParallelFeatureOperations() throws {
        let rumServerSession = server.obtainUniqueRecordingSession()
        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "RUMFeatureOperationsScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumServerSession.recordingURL
            )
        )

        let screen = ExampleApplication()

        // Test parallel photo uploads with different keys
        screen.tapStartConcurrentOperations()
        screen.tapSucceedConcurrentOperations()

        try app.endRUMSession()

        let recordedRUMRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.singleSession(from: requests)?.hasEnded() ?? false
        }

        assertRUM(requests: recordedRUMRequests)
        let session = try XCTUnwrap(RUMSessionMatcher.singleSession(from: recordedRUMRequests))

        // Verify parallel operations vital events
        let vitalEvents = session.vitalEvents
        let photoUploadStartEvents = vitalEvents.filter { $0.vital.name == "photo_upload" && $0.vital.stepType == .start }
        let photoUploadSucceedEvents = vitalEvents.filter { $0.vital.name == "photo_upload" && $0.vital.stepType == .end && $0.vital.failureReason == nil }

        XCTAssertEqual(photoUploadStartEvents.count, 3, "Should have three photo upload start events")
        XCTAssertEqual(photoUploadSucceedEvents.count, 3, "Should have three photo upload succeed events")

        // Verify operation keys for parallel instances
        let operationKeys = Set(vitalEvents.compactMap { $0.vital.operationKey })
        let expectedKeys = Set(["photo1", "photo2", "photo3"])
        XCTAssertEqual(operationKeys, expectedKeys, "Parallel operations should have the correct operation keys")
    }

    func testParallelFeatureOperationsWithFailure() throws {
        let rumServerSession = server.obtainUniqueRecordingSession()
        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "RUMFeatureOperationsScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumServerSession.recordingURL
            )
        )

        let screen = ExampleApplication()

        // Test parallel photo uploads with different keys
        screen.tapStartConcurrentOperations()
        screen.tapFailConcurrentOperations()

        try app.endRUMSession()

        let recordedRUMRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.singleSession(from: requests)?.hasEnded() ?? false
        }

        assertRUM(requests: recordedRUMRequests)
        let session = try XCTUnwrap(RUMSessionMatcher.singleSession(from: recordedRUMRequests))

        // Verify parallel operations vital events
        let vitalEvents = session.vitalEvents
        let startEvents = vitalEvents.filter { $0.vital.name == "photo_upload" && $0.vital.stepType == .start }
        let failureEvents = vitalEvents.filter {
            $0.vital.name == "photo_upload" &&
            $0.vital.stepType == .end &&
            $0.vital.failureReason != nil
        }

        XCTAssertEqual(startEvents.count, 3, "Should have three photo upload start events")
        XCTAssertEqual(failureEvents.count, 3, "Should have three photo upload failure events")

        let expectedFailures = [
            ("photo1", RUMVitalEvent.Vital.FailureReason.error),
            ("photo2", RUMVitalEvent.Vital.FailureReason.abandoned),
            ("photo3", RUMVitalEvent.Vital.FailureReason.other)
        ]

        zip(failureEvents.sorted { $0.vital.operationKey ?? "" < $1.vital.operationKey ?? "" }, expectedFailures)
        .forEach { event, expectedFailure in
            XCTAssertEqual(event.vital.operationKey, expectedFailure.0)
            XCTAssertEqual(event.vital.failureReason, expectedFailure.1)
        }
    }

    // MARK: - Multiple Views Test

    func testFeatureOperationAcrossMultipleViews() throws {
        let rumServerSession = server.obtainUniqueRecordingSession()
        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "RUMFeatureOperationsScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumServerSession.recordingURL
            )
        )

        let screen = ExampleApplication()

        // Start operation in current view
        screen.tapStartLoginFlow()
        
        // Navigate to next screen (operation continues)
        screen.tapPushNextScreen()
        
        // Complete operation in different view
        screen.tapSucceedLoginOnNextView()

        screen.swipeDown(velocity: XCUIGestureVelocity.fast)

        try app.endRUMSession()

        let recordedRUMRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.singleSession(from: requests)?.hasEnded() ?? false
        }

        assertRUM(requests: recordedRUMRequests)
        let session = try XCTUnwrap(RUMSessionMatcher.singleSession(from: recordedRUMRequests))
        print("session: \(session)")

        // Verify we have multiple views
        XCTAssertGreaterThan(session.views.count, 2, "Should have multiple views")

        // Verify vital events capture the correct view context
        let vitalEvents = session.vitalEvents
        let loginStartEvents = vitalEvents.filter { $0.vital.name == "login_flow" && $0.vital.stepType == .start }
        let loginSucceedEvents = vitalEvents.filter { $0.vital.name == "login_flow" && $0.vital.stepType == .end && $0.vital.failureReason == nil }

        XCTAssertEqual(loginStartEvents.count, 1, "Should have one login flow start event")
        XCTAssertEqual(loginSucceedEvents.count, 1, "Should have one login flow succeed event")

        // Verify start event is associated with 1st view
        let startEvent = try XCTUnwrap(loginStartEvents.first)
        let firstView = session.views[1] // Skip application launch view
        XCTAssertEqual(startEvent.view.id, firstView.viewID, "Start event should be associated with the view where it was started")

        // Verify second event is associated with 2nd view
        let secondEvent = try XCTUnwrap(loginSucceedEvents.first)
        let secondView = session.views[2]
        XCTAssertEqual(secondEvent.view.id, secondView.viewID, "Second event should be associated with the view where it was started")
    }
}
