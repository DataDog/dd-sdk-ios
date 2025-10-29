/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import TestUtilities
import XCTest

private extension ExampleApplication {
    /// Tapping this button will crash the app.
    func tapCallFatalError() {
        tapButton(titled: "Call fatalError()")
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
            let firstSessionHasError = sessions.first?.errorEventMatchers.count == 1
            return thereAreTwoSessions && firstSessionHasError
        }

        assertRUM(requests: recordedRequests)

        let sessions = try RUMSessionMatcher.sessions(maxCount: 2, from: recordedRequests)
            .sorted { session1, session2 in
                // Sort sessions by their startTimestamp
                return session1.views[0].startTimestampMs < session2.views[0].startTimestampMs
            }
        let crashedSession = try XCTUnwrap(sessions.first)
        sendCIAppLog("Crashed session: \n\(crashedSession)")

        let initialView = crashedSession.views[0]
        XCTAssertTrue(initialView.isApplicationLaunchView(), "The session should start with 'application launch' view")
        XCTAssertNotNil(crashedSession.ttidEvent)

        XCTAssertEqual(crashedSession.views[1].name, "Runner.CrashReportingViewController")
        XCTAssertEqual(
            crashedSession.views[1].viewEvents.last?.view.crash?.count,
            1,
            "The RUM View should count the crash."
        )
        XCTAssertEqual(
            crashedSession.views[1].errorEvents.count,
            1,
            "The RUM View should count 1 error in total."
        )

        let crashRUMError = try XCTUnwrap(crashedSession.views[1].errorEvents.last)
        XCTAssertEqual(crashRUMError.version, "1.0")
        XCTAssertEqual(crashRUMError.buildVersion, "1")

#if arch(arm64)
        XCTAssertEqual(crashRUMError.error.message, "Application crash: SIGTRAP (Trace/BPT trap)", "On ARM, the crash is caused by `fatalError()`, translates to `SIGTRAP` signal.")
        XCTAssertEqual(crashRUMError.error.type, "SIGTRAP (#0)")
#elseif arch(x86_64)
        XCTAssertEqual(crashRUMError.error.message, "Application crash: SIGILL (Illegal instruction)", "On x86, the crash is caused by `fatalError()`, translates to `SIGILL` signal.")
        XCTAssertEqual(crashRUMError.error.type, "SIGILL (ILL_ILLOPC)")
#else
        XCTFail("Unsupported architecture")
#endif
        XCTAssertNotNil(crashRUMError.error.stack)

        // Assert superficial properties of sending crash information:
        let lastRUMErrorEventMatcherInCrashedSession = try XCTUnwrap(crashedSession.errorEventMatchers.last)
        let lastRUMErrorEventJSON = lastRUMErrorEventMatcherInCrashedSession.jsonMatcher
        XCTAssertNotNil(try? lastRUMErrorEventJSON.value(forKeyPath: "error.meta") as [String: Any], "The error should include crash meta info")
        XCTAssertNotNil(try? lastRUMErrorEventJSON.value(forKeyPath: "error.threads") as [Any], "The error should include threads info")
        XCTAssertNotNil(try? lastRUMErrorEventJSON.value(forKeyPath: "error.binary_images") as [Any], "The error should include binary images info")

        // Assert mapped value
        XCTAssertEqual(crashRUMError.error.fingerprint, "mapped fingerprint", "Error should have a mapper supplied fingerprint value")
    }
}
