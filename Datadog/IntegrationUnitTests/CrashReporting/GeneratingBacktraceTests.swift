/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogCrashReporting
@testable import DatadogInternal

/// Tests integration of `DatadogCore` and `DatadogCrashReporting` for backtrace generation.
class GeneratingBacktraceTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy(context: .mockWith(trackingConsent: .granted))
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    func testGivenCrashReportingIsEnabled_thenCoreCanGenerateBacktrace() throws {
        // Given
        CrashReporting.enable(in: core)
        XCTAssertNotNil(core.get(feature: BacktraceReportingFeature.self), "`BacktraceReportingFeature` is registered")

        // When
        let backtrace = try XCTUnwrap(core.backtraceReporter.generateBacktrace())

        // Then
        XCTAssertGreaterThan(backtrace.threads.count, 0, "Some thread(s) should be recorded")
        XCTAssertGreaterThan(backtrace.binaryImages.count, 0, "Some binary image(s) should be recorded")

        XCTAssertTrue(
            backtrace.stack.contains("DatadogCoreTests"),
            "Backtrace stack should include at least one frame from `DatadogCoreTests` image"
        )
        XCTAssertTrue(
            backtrace.stack.contains("XCTest"),
            "Backtrace stack should include at least one frame from `XCTest` image"
        )
        #if os(iOS)
        XCTAssertTrue(
            backtrace.binaryImages.contains(where: { $0.libraryName == "DatadogCoreTests iOS" }),
            "Backtrace should include the image for `DatadogCoreTests iOS`"
        )
        #elseif os(tvOS)
        XCTAssertTrue(
            backtrace.binaryImages.contains(where: { $0.libraryName == "DatadogCoreTests tvOS" }),
            "Backtrace should include the image for `DatadogCoreTests tvOS`"
        )
        #endif
        XCTAssertTrue(
            // Assert on prefix as it is `XCTestCore` on iOS 15+ and `XCTest` earlier:
            backtrace.binaryImages.contains(where: { $0.libraryName.hasPrefix("XCTest") }),
            "Backtrace should include the image for `XCTest`"
        )
    }
}
