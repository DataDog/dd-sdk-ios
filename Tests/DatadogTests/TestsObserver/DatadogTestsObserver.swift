/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

/// Observes unit tests execution and performs integrity checks after each test to ensure that the global state is unaltered.
@objc
internal class DatadogTestsObserver: NSObject, XCTestObservation {
    @objc
    static func startObserving() {
        let observer = DatadogTestsObserver()
        XCTestObservationCenter.shared.addTestObserver(observer)
    }

    // MARK: - Checking Tests Integrity

    /// A list of checks ensuring global state integrity before and after each tests.
    private let checks: [TestIntegrityCheck] = [
        .init(
            assert: { Datadog.instance == nil },
            problem: "`Datadog` must not be initialized.",
            solution: """
            Make sure `Datadog.flushAndDeinitialize()` is called before the end of test that uses `Datadog.initialize()`.
            """
        ),
        .init(
            assert: {
                Global.sharedTracer is DDNoopTracer
                    && Global.rum is DDNoopRUMMonitor
                    && Global.crashReporter == nil
            },
            problem: "All Global components must use no-op implementations.",
            solution: """
            Make sure each Global component is reset to its default implementation before the end of test that mocks it:
            ```
            Global.sharedTracer = DDNoopGlobals.tracer
            Global.rum = DDNoopRUMMonitor()
            Global.crashReporter = nil
            ```
            """
        ),
        .init(
            assert: {
                LoggingFeature.instance == nil
                    && TracingFeature.instance == nil
                    && RUMFeature.instance == nil
                    && CrashReportingFeature.instance == nil
                    && InternalMonitoringFeature.instance == nil
            },
            problem: "All features must not be initialized.",
            solution: """
            Make sure `{Feature}.instance?.deinitialize()` is called before the end of test that uses `{Feature}.instance` mock.
            """
        ),
        .init(
            assert: {
                RUMAutoInstrumentation.instance == nil && URLSessionAutoInstrumentation.instance == nil
            },
            problem: "All auto-instrumentation features must not be initialized.",
            solution: """
            Make sure `{AutoInstrumentationFeature}.instance?.deinitialize()` is called before the end of test that
            uses `{AutoInstrumentationFeature}.instance` mock.
            """
        ),
        .init(
            assert: { activeSwizzlingNames.isEmpty },
            problem: "No swizzling must be applied.",
            solution: """
            Make sure all applied swizzling are reset by the end of test with `unswizzle()`.

            `DatadogTestsObserver` found \(activeSwizzlingNames.count) leaked swizzlings:
            \(activeSwizzlingNames.joined(separator: ", "))
            """
        ),
        .init(
            assert: { userLogger.logBuilder == nil && userLogger.logOutput == nil },
            problem: "`userLogger` must use no-op implementation.",
            solution: """
            Make sure the `userLogger` is captured before test and reset to the previous implementation after, e.g.:

            ```
            let previousUserLogger = userLogger
            defer { userLogger = previousUserLogger }
            ```
            """
        ),
        .init(
            assert: { ServerMock.activeInstance == nil },
            problem: "`ServerMock` must not be active.",
            solution: """
            Make sure that test waits for `ServerMock` completion at the end:

            ```
            let server = ServerMock(...)

            // ... testing

            server.wait<...>(...) // <-- after return, no reference to `server` will exist as it processed all callbacks and got be safely deallocated
            ```
            """
        ),
        .init(
            assert: {
                temporaryFeatureDirectories.authorized.exists() == false
                    && temporaryFeatureDirectories.unauthorized.exists() == false
            },
            problem: "`temporaryFeatureDirectories` must not exist.",
            solution: """
            Make sure that `temporaryFeatureDirectories` is unifromly managed in every test by using:
            ```
            // Before test:
            temporaryFeatureDirectories.create()

            // After test:
            temporaryFeatureDirectories.delete()
            ```
            """
        )
    ]

    func testCaseDidFinish(_ testCase: XCTestCase) {
        if testCase.testRun?.hasSucceeded == true {
            performIntegrityChecks(after: testCase)
        }
    }

    private func performIntegrityChecks(after testCase: XCTestCase) {
        let failedChecks = checks.filter { $0.assert() == false }

        if !failedChecks.isEmpty {
            var message = """
            🐶✋ `DatadogTests` integrity check failure.

            `DatadogTestsObserver` found that `\(testCase.name)` breaks \(failedChecks.count) integrity rule(s) which
            must be fulfilled before and after each unit test:
            """
            failedChecks.forEach { check in
                message += """
                \n⚠️ ---- \(check.problem) ----
                🔎 \(check.solution())
                """
            }

            message += "\n"
            preconditionFailure(message)
        }
    }
}

private struct TestIntegrityCheck {
    /// If this assertion evaluates to `false`, the integrity issue is raised.
    let assert: () -> Bool
    /// What is the assertion about?
    let problem: StaticString
    /// How to fix it if it fails?
    let solution: () -> String

    init(assert: @escaping () -> Bool, problem: StaticString, solution: @escaping @autoclosure () -> String) {
        self.assert = assert
        self.problem = problem
        self.solution = solution
    }
}
