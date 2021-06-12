/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest

private extension ExampleApplication {
    /// Tapping this button will crash the app.
    func tapCallFatalError() {
        buttons["Call fatalError()"].tap()
    }
}

class CrashReportingWithRUMScenarioTests: IntegrationTests, RUMCommonAsserts {
    /// Launches the app, taps "Call fatalError()" button (leading to crash), then restarts the app
    /// to have the crash report uploaded to RUM endpoint.
    ///
    /// Note: To run this test on the local machine, debugger must be disconnected, otherwise it will catch the crash
    /// before the SDK. CI runs all tests through CLI with no debugger attached.
    func testCrashReportingCollectOrSendWithRUMScenario() throws {
        let rumServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "CrashReportingCollectOrSendWithRUMScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumServerSession.recordingURL
            ),
            clearPersistentData: true
        )

        app.tapCallFatalError() // crash the app

        app.launchWith(
            testScenarioClassName: "CrashReportingCollectOrSendWithRUMScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumServerSession.recordingURL
            ),
            clearPersistentData: false // do not clear data from previous session
        )

        // Pull requests until two RUM Sessions are received and the first one has associated RUM Error event
        let recordedRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            let sessions = try RUMSessionMatcher.sessions(maxCount: 2, from: requests)
            let thereAreTwoSessions = sessions.count == 2
            let firstSessionHasError = sessions.first?.viewVisits.first?.errorEvents.count == 1
            return thereAreTwoSessions && firstSessionHasError
        }

        assertRUM(requests: recordedRequests)

        let sessions = try RUMSessionMatcher.sessions(maxCount: 2, from: recordedRequests)
            .sorted { session1, session2 in
                // Sort sessions by their "application_start" action date
                return session1.viewVisits[0].actionEvents[0].date < session2.viewVisits[0].actionEvents[0].date
            }
        let crashedSession = try XCTUnwrap(sessions.first)

        XCTAssertEqual(crashedSession.viewVisits[0].name, "Example.CrashReportingViewController")
        XCTAssertEqual(
            crashedSession.viewVisits[0].viewEvents.last?.view.crash?.count,
            1,
            "The RUM View should count the crash."
        )
        XCTAssertEqual(
            crashedSession.viewVisits[0].errorEvents.count,
            1,
            "The RUM View should count 1 error in total."
        )

        let crashRUMError = try XCTUnwrap(crashedSession.viewVisits[0].errorEvents.last)
        XCTAssertEqual(crashRUMError.error.message, "Illegal instruction")
        XCTAssertEqual(crashRUMError.error.type, "SIGILL (ILL_ILLOPC)")
        XCTAssertNotNil(crashRUMError.error.stack)
    }
}
