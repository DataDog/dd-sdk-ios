/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal
@testable import DatadogCore

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
            assert: { CoreRegistry.instances.isEmpty },
            problem: "No instance of `DatadogCore` must be left initialized after test completion.",
            solution: """
            Make sure deinitialization APIs are called before the end of test that registers `DatadogCore`.
            If registering directly to `CoreRegistry`, make sure the test cleans it up properly.

            `DatadogTestsObserver` found following instances still being registered: \(CoreRegistry.instances.map({ "'\($0.key)'" }))
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
            assert: { URLSessionSwizzler.bindingsCount == 0 },
            problem: "No `URLSessionSwizzler` must be bonded.",
            solution: """
            Make sure all applied `URLSessionSwizzler.bind()` are reset by the end of test with `URLSessionSwizzler.unbind()`.

            `DatadogTestsObserver` found \(URLSessionSwizzler.bindingsCount) bindings left.
            """
        ),
        .init(
            assert: { DD.logger is InternalLogger },
            problem: "`DD.logger` must use `InternalLogger` implementation.",
            solution: """
            Make sure the `DD` bundle is reset after test to use previous dependencies, e.g.:

            ```
            let dd = DD.mockWith(logger: CoreLoggerMock())
            defer { dd.reset() }
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
            assert: { !FileManager.default.fileExists(atPath: temporaryDirectory.path) },
            problem: "`temporaryDirectory` must not exist.",
            solution: """
            Make sure `DeleteTemporaryDirectory()` is called consistently
            with `CreateTemporaryDirectory()`.
            """
        ),
        .init(
            assert: { !temporaryCoreDirectory.coreDirectory.exists()
                && !temporaryCoreDirectory.osDirectory.exists()
            },
            problem: "`temporaryCoreDirectory` must not exist.",
            solution: """
            Make sure `temporaryCoreDirectory.delete()` is called consistently
            with `temporaryCoreDirectory.create()`.
            """
        ),
        .init(
            assert: {
                !temporaryFeatureDirectories.authorized.exists()
                    && !temporaryFeatureDirectories.unauthorized.exists()
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
        ),
        .init(
            assert: { DatadogCoreProxy.referenceCount == 0 },
            problem: "Leaking reference to `DatadogCoreProtocol`",
            solution: """
            There should be no remaining reference to `DatadogCoreProtocol` upon each test completion
            but some instances of `DatadogCoreProxy` are still alive.

            Make sure the instance of `DatadogCoreProxy` is properly managed in test:
            - it must be allocated on each test start (e.g. in `setUp()` or directly in test)
            - it must be flushed and deinitialized before test ends with `.flushAndTearDown()`
            - it must be deallocated before test ends (e.g. in `tearDown()`)

            If all above conditions are met, this failure might indicate a memory leak in the implementation.

            \(DatadogCoreProxy.stackTrace)
            """
        ),
        .init(
            assert: { PassthroughCoreMock.referenceCount == 0 },
            problem: "Leaking reference to `DatadogCoreProtocol`",
            solution: """
            There should be no remaining reference to `DatadogCoreProtocol` upon each test completion
            but some instances of `PassthroughCoreMock` are still alive.

            Make sure the instance of `PassthroughCoreMock` is properly managed in test:
            - it must be allocated on each test test start (e.g. in `setUp()` or directly in test)
            - it must be deallocated before test ends (e.g. in `tearDown()`)

            If all above conditions are met, this failure might indicate a memory leak in the implementation.

            \(PassthroughCoreMock.stackTrace)
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
            must be fulfilled before and after each unit test. Find potential root cause analysis below and try running
            surrounding tests in isolation to pinpoint the issue:
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
