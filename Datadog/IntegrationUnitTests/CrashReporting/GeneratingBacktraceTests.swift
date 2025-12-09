/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogCrashReporting
@testable import DatadogInternal

/// Tests integration of `DatadogCore` and `DatadogCrashReporting` for backtrace generation.
class GeneratingBacktraceTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy(context: .mockWith(trackingConsent: .granted))
    }

    override func tearDownWithError() throws {
        try core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    func testGeneratingBacktraceOfTheCurrentThread() throws {
        // Given
        CrashReporting._internal.kscrash_enable(in: core)
        XCTAssertNotNil(core.get(feature: BacktraceReportingFeature.self), "`BacktraceReportingFeature` must be registered")

        // When
        let backtrace = try XCTUnwrap(core.backtraceReporter.generateBacktrace())

        // Then
        XCTAssertGreaterThan(backtrace.threads.count, 0, "Some thread(s) should be recorded")
        XCTAssertGreaterThan(backtrace.binaryImages.count, 0, "Some binary image(s) should be recorded")
        XCTAssertFalse(backtrace.threads.contains(where: { $0.crashed }), "No thread should be marked as crashed")

        XCTAssertTrue(
            backtrace.stack.contains("DatadogIntegrationTests"),
            "Backtrace stack should include at least one frame from `DatadogCoreTests` image"
        )
        XCTAssertTrue(
            backtrace.stack.contains("XCTest"),
            "Backtrace stack should include at least one frame from `XCTest` image"
        )
        #if os(iOS)
        XCTAssertTrue(
            backtrace.binaryImages.contains(where: { $0.libraryName == "DatadogIntegrationTests iOS" }),
            "Backtrace should include the image for `DatadogCoreTests iOS`"
        )
        #elseif os(tvOS)
        XCTAssertTrue(
            backtrace.binaryImages.contains(where: { $0.libraryName == "DatadogIntegrationTests tvOS" }),
            "Backtrace should include the image for `DatadogCoreTests tvOS`"
        )
        #endif
        XCTAssertTrue(
            // Assert on prefix as it is `XCTestCore` on iOS 15+ and `XCTest` earlier:
            backtrace.binaryImages.contains(where: { $0.libraryName.hasPrefix("XCTest") }),
            "Backtrace should include the image for `XCTest`"
        )
    }

    func testGeneratingBacktraceOfTheMainThread() throws {
        // Given
        CrashReporting._internal.kscrash_enable(in: core)

        // When
        XCTAssertTrue(Thread.current.isMainThread)
        let threadID = Thread.currentThreadID
        let backtrace = try XCTUnwrap(core.backtraceReporter.generateBacktrace(threadID: threadID))

        // Then
        XCTAssertFalse(backtrace.stack.isEmpty)
        XCTAssertTrue(backtrace.stack.contains(uiKitLibraryName), "Main thread stack should include UIKit symbols")
    }

    func testGeneratingBacktraceOfSecondaryThread() throws {
        // Given
        CrashReporting._internal.kscrash_enable(in: core)

        // When
        let semaphore = DispatchSemaphore(value: 0)
        var threadID: ThreadID?

        let thread = Thread {
            XCTAssertFalse(Thread.current.isMainThread)
            threadID = Thread.currentThreadID
            semaphore.signal()
            Thread.sleep(forTimeInterval: 1)
        }

        thread.start()
        XCTAssertEqual(semaphore.wait(timeout: .now() + 5), .success)
        thread.cancel()

        let backtrace = try XCTUnwrap(core.backtraceReporter.generateBacktrace(threadID: threadID!))

        // Then
        XCTAssertFalse(backtrace.stack.isEmpty)
        XCTAssertFalse(backtrace.stack.contains(uiKitLibraryName), "Secondary thread stack should NOT include UIKit symbols")
    }
}
