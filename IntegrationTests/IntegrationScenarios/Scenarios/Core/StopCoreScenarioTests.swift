/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import HTTPServerMock
import XCTest

private class CSRootScreen: XCUIApplication {
    func startCore() {
        buttons["Start Core"].tap()
    }

    func stopCore() {
        buttons["Stop Core"].tap()
    }

    func tapGoToHome() -> CSHomeScreen {
        buttons["Go To Home"].tap()
        return CSHomeScreen()
    }
}

private class CSHomeScreen: XCUIApplication {
    func tapTestLogging() {
        buttons["Test Logging"].tap()
    }

    func tapTestTracing() {
        buttons["Test Tracing"].tap()
    }

    func tapTestRUM() -> CSPictureScreen {
        buttons["Test RUM"].tap()
        return CSPictureScreen()
    }

    func tapBack() -> CSRootScreen {
        navigationBars["Runner.CSHomeView"].buttons["Back"].tap()
        return CSRootScreen()
    }
}

private class CSPictureScreen: XCUIApplication {
    func tapDownloadImage() {
        buttons["Download image"].tap()
    }

    func waitForImageBeingDownloaded() {
        _ = staticTexts["☑️"].waitForExistence(timeout: 10)
    }

    func tapBack() -> CSHomeScreen {
        navigationBars["Runner.CSPictureView"].buttons["Back"].tap()
        return CSHomeScreen()
    }
}

class StopCoreScenarioTests: IntegrationTests, LoggingCommonAsserts, TracingCommonAsserts, RUMCommonAsserts {
    func testStartAndStopCoreInstance() throws {
        let loggingServerSession = server.obtainUniqueRecordingSession()
        let tracingServerSession = server.obtainUniqueRecordingSession()
        let rumServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "StopCoreScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                logsEndpoint: loggingServerSession.recordingURL,
                tracesEndpoint: tracingServerSession.recordingURL,
                rumEndpoint: rumServerSession.recordingURL
            )
        )

        // Play scenarios

        var root = playScenario()

        try assertLoggingDataWasCollected(by: loggingServerSession)
        try assertTracingDataWasCollected(by: tracingServerSession)
        try assertRUMDataWasCollected(by: rumServerSession)
        server.clearAllRequests()

        root.stopCore()
        root = playScenario(from: root)

        Thread.sleep(forTimeInterval: dataDeliveryTimeout)

        let recordedLoggingRequests = try loggingServerSession.getRecordedRequests()
        XCTAssertEqual(recordedLoggingRequests.count, 0, "No logging data should be send.")
        let recordedTracingRequests = try loggingServerSession.getRecordedRequests()
        XCTAssertEqual(recordedTracingRequests.count, 0, "No tracing data should be send.")
        let recordedRUMRequests = try rumServerSession.getRecordedRequests()
        XCTAssertEqual(recordedRUMRequests.count, 0, "No RUM data should be send.")

        root.startCore()
        root = playScenario(from: root)

        try assertLoggingDataWasCollected(by: loggingServerSession)
        try assertTracingDataWasCollected(by: tracingServerSession)
        try assertRUMDataWasCollected(by: rumServerSession)
    }

    /// Plays following scenario for started application:
    /// * sends log and trace from home screen,
    /// * goes to picture screen and downloads the image,
    /// * goes back to the home screen.
    private func playScenario(from root: CSRootScreen = CSRootScreen()) -> CSRootScreen {
        let home = root.tapGoToHome()
        home.tapTestLogging()
        home.tapTestTracing()
        let pictureScreen = home.tapTestRUM()
        pictureScreen.tapDownloadImage()
        pictureScreen.waitForImageBeingDownloaded()
        return pictureScreen
            .tapBack()
            .tapBack()
    }

    // MARK: - Data assertions

    private func assertLoggingDataWasCollected(by serverSession: ServerSession) throws {
        let recordedRequests = try serverSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try LogMatcher.from(requests: requests).count == 1
        }

        assertLogging(requests: recordedRequests)

        let logMatchers = try LogMatcher.from(requests: recordedRequests)
        XCTAssertEqual(logMatchers.count, 1)
        let logMatcher = logMatchers[0]
        logMatcher.assertMessage(equals: "test message")
        logMatcher.assertStatus(equals: "info")
    }

    private func assertTracingDataWasCollected(by serverSession: ServerSession) throws {
        let recordedRequests = try serverSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try SpanMatcher.from(requests: requests).count == 1
        }

        assertTracing(requests: recordedRequests)

        let spanMatchers = try SpanMatcher.from(requests: recordedRequests)
        XCTAssertEqual(spanMatchers.count, 1)
        let spanMatcher = spanMatchers[0]
        XCTAssertEqual(try spanMatcher.operationName(), "test span")
    }

    private func assertRUMDataWasCollected(by serverSession: ServerSession) throws {
        let recordedRequests = try serverSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            // ignore telemetry and application start view events
            let eventMatchers = try requests
                .flatMap { request in try RUMEventMatcher.fromNewlineSeparatedJSONObjectsData(request.httpBody) }
                .filterTelemetry()
                .filterApplicationLaunchView()

            guard let session = try RUMSessionMatcher.groupMatchersBySessions(eventMatchers).first else {
                return false
            }

            return session.views.count >= 3
        }

        assertRUM(requests: recordedRequests)

        // ignore telemetry and application start view events
        let eventMatchers = try recordedRequests
            .flatMap { request in try RUMEventMatcher.fromNewlineSeparatedJSONObjectsData(request.httpBody) }
            .filterTelemetry()
            .filterApplicationLaunchView()

        let session = try XCTUnwrap(RUMSessionMatcher.groupMatchersBySessions(eventMatchers).first)
        sendCIAppLog(session)

        XCTAssertEqual(session.views[0].name, "Home")
        XCTAssertGreaterThan(session.views[0].actionEvents.count, 0)

        XCTAssertEqual(session.views[1].name, "Picture")
        XCTAssertEqual(session.views[1].resourceEvents.count, 1)
        XCTAssertGreaterThan(session.views[1].actionEvents.count, 0)

        XCTAssertEqual(session.views[2].name, "Home")
    }
}
