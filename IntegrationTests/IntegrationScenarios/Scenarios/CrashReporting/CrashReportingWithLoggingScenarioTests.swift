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
        buttons["Call fatalError()"].safeTap()
    }
}

class CrashReportingWithLoggingScenarioTests: IntegrationTests, LoggingCommonAsserts {
    /// Launches the app, taps "Call fatalError()" button (leading to crash), then restarts the app
    /// to have the crash report uploaded to logging endpoint.
    ///
    /// Note: To run this test on the local machine, debugger must be disconnected, otherwise it will catch the crash
    /// before the SDK. CI runs all tests through CLI with no debugger attached.
    func testCrashReportingCollectOrSendWithLoggingScenario() throws {
        let loggingServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "CrashReportingCollectOrSendWithLoggingScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                logsEndpoint: loggingServerSession.recordingURL
            ),
            clearPersistentData: true
        )

        app.tapCallFatalError() // crash the app

        app.launchWith(
            testScenarioClassName: "CrashReportingCollectOrSendWithLoggingScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                logsEndpoint: loggingServerSession.recordingURL
            ),
            clearPersistentData: false // do not clear data from previous session
        )

        let recordedRequests = try loggingServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try LogMatcher.from(requests: requests).count >= 1
        }
        let logMatchers = try LogMatcher.from(requests: recordedRequests)

        // Assert common things
        assertLogging(requests: recordedRequests)

        let crashLog = logMatchers[0]
        crashLog.assertDate(matches: { Date().timeIntervalSince($0) < dataDeliveryTimeout * 2 })

        // Assert crash report info
        crashLog.assertStatus(equals: "emergency")
#if arch(arm64)
        // On ARM, the crash is caused by `fatalError()`, translates to `SIGTRAP` signal.
        crashLog.assertMessage(equals: "Application crash: SIGTRAP (Trace/BPT trap)")
        crashLog.assertAttributes(
            equal: [
                LogMatcher.JSONKey.errorKind: "SIGTRAP (#0)",
                LogMatcher.JSONKey.errorMessage: "Application crash: SIGTRAP (Trace/BPT trap)",
            ]
        )
#elseif arch(x86_64)
        // On x86, the crash is caused by `fatalError()`, translates to `SIGILL` signal.
        crashLog.assertMessage(equals: "Application crash: SIGILL (Illegal instruction)")
        crashLog.assertAttributes(
            equal: [
                LogMatcher.JSONKey.errorKind: "SIGILL (ILL_ILLOPC)",
                LogMatcher.JSONKey.errorMessage: "Application crash: SIGILL (Illegal instruction)",
            ]
        )
#else
        XCTFail("Unsupported architecture")
#endif

        crashLog.assertAttributes(equal: [
            "global-attribute": "string-a",
            "global-attribute-2": 1_150
        ])

        crashLog.assertValue(
            forKeyPath: LogMatcher.JSONKey.errorStack,
            isTypeOf: String.self
        )

        // Assert user info
        crashLog.assertUserInfo(
            equals: (
                id: "abcd-1234",
                name: "foo",
                email: "foo@example.com"
            )
        )

        // Assert network info
        crashLog.assertValue(
            forKeyPath: LogMatcher.JSONKey.networkReachability,
            matches: { LogMatcher.allowedNetworkReachabilityValues.contains($0) }
        )

        // Assert other characteristics important for crash reporting
        crashLog.assertService(equals: "ui-tests-service-name")
        crashLog.assertLoggerName(equals: "crash-reporter")
        crashLog.assertApplicationVersion(equals: "1.0")
        crashLog.assertApplicationBuildNumber(equals: "1")

        // Assert mapped value
        crashLog.assertErrorFingerprint(equals: "mapped fingerprint")
    }
}
