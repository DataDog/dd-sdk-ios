/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
import DatadogCrashReporting
@testable import DatadogRUM

/// Test case covering scenarios of App Hangs monitoring in RUM.
class AppHangsMonitoringTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional
    private var rumConfig = RUM.Configuration(applicationID: .mockAny())
    private var hangDuration: TimeInterval! // swiftlint:disable:this implicitly_unwrapped_optional
    /// Use main queue mock, otherwise any `waitForExpectations(timeout:)` would be considered an app hang and may cause dead locks.
    private let mainQueue = DispatchQueue(label: "main-queue-mock", qos: .userInteractive)

    private var expectedHangDurationRangeNs: ClosedRange<Int64> {
        let min = hangDuration.dd.toInt64Nanoseconds / 2 // -50% margin
        let max = hangDuration.dd.toInt64Nanoseconds * 5 // +500% margin to avoid flakiness
        return (min...max)
    }

    override func setUp() {
        rumConfig.mainQueue = mainQueue
        rumConfig.appHangThreshold = 0.4
        hangDuration = rumConfig.appHangThreshold! * 1.25
        core = DatadogCoreProxy()
    }

    override func tearDownWithError() throws {
        try core.flushAndTearDown()
        core = nil
    }

    func testWhenMainThreadIsHangedInitially_itTracksAppHangError() throws {
        // Given
        mainQueue.sync {
            RUM.enable(with: rumConfig, in: core)

            // When
            Thread.sleep(forTimeInterval: hangDuration) // hang right after SDK is initialized
        }

        // Then
        try flushHangsMonitoring()
        let errors = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMErrorEvent.self)
        let appHangError = try XCTUnwrap(errors.first)
        let actualHangDuration = try XCTUnwrap(appHangError.freeze?.duration)

        XCTAssertEqual(appHangError.error.message, AppHangsMonitor.Constants.appHangErrorMessage)
        XCTAssertEqual(appHangError.error.type, AppHangsMonitor.Constants.appHangErrorType)
        XCTAssertEqual(appHangError.error.category, .appHang)
        XCTAssertTrue(expectedHangDurationRangeNs.contains(actualHangDuration))
    }

    func testWhenMainThreadIsHangedAfterInit_itTracksAppHangError() throws {
        // Given
        mainQueue.sync {
            RUM.enable(with: rumConfig, in: core)
        }

        // When
        mainQueue.sync { // hang in the main thread task that follows SDK is initialization
            Thread.sleep(forTimeInterval: hangDuration)
        }

        // Then
        try flushHangsMonitoring()
        let errors = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMErrorEvent.self)
        let appHangError = try XCTUnwrap(errors.first)
        let actualHangDuration = try XCTUnwrap(appHangError.freeze?.duration)

        XCTAssertEqual(appHangError.error.message, AppHangsMonitor.Constants.appHangErrorMessage)
        XCTAssertEqual(appHangError.error.type, AppHangsMonitor.Constants.appHangErrorType)
        XCTAssertEqual(appHangError.error.category, .appHang)
        XCTAssertTrue(expectedHangDurationRangeNs.contains(actualHangDuration))
    }

    func testGivenRUMAndCrashReportingEnabled_whenMainThreadHangs_thenAppHangErrorIncludesStackTrace() throws {
        #if os(watchOS)
        throw XCTSkip("Backtrace generation is not supported on watchOS (thread_get_state unavailable)")
        #else
        // Given (initialize SDK on the main thread)
        oneOf([ // no matter of RUM or CR initialization order
            {
                RUM.enable(with: self.rumConfig, in: self.core)
                CrashReporting.enable(in: self.core)
            },
            {
                CrashReporting.enable(in: self.core)
                RUM.enable(with: self.rumConfig, in: self.core)
            },
        ])

        // When
        mainQueue.sync {
            Thread.sleep(forTimeInterval: hangDuration)
        }

        // Then
        try flushHangsMonitoring()
        let errors = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMErrorEvent.self)
        let appHangError = try XCTUnwrap(errors.first)
        let mainThreadStack = try XCTUnwrap(appHangError.error.stack)

        XCTAssertEqual(appHangError.error.message, AppHangsMonitor.Constants.appHangErrorMessage)
        XCTAssertEqual(appHangError.error.type, AppHangsMonitor.Constants.appHangErrorType)
        XCTAssertTrue(mainThreadStack.contains("XCTestCore"), "Main thread stack should include XCTestCore symbols")
        XCTAssertEqual(appHangError.error.source, .source)
        XCTAssertNotNil(appHangError.error.threads, "Other threads should be available")
        XCTAssertNotNil(appHangError.error.binaryImages,  "Binary Images should be available for symbolication")
        #endif
    }

    func testGivenAppHangBacktracesDisabledInCrashReporting_whenRUMIsEnabledFirst_itTracksAppHangWithNoStackTrace() throws {
        try assertAppHangIsTrackedWithNoStackTrace { crashReportingConfig in
            RUM.enable(with: self.rumConfig, in: self.core)
            CrashReporting.enable(with: crashReportingConfig, in: self.core)
        }
    }

    func testGivenAppHangBacktracesDisabledInCrashReporting_whenCrashReportingIsEnabledFirst_itTracksAppHangWithNoStackTrace() throws {
        try assertAppHangIsTrackedWithNoStackTrace { crashReportingConfig in
            CrashReporting.enable(with: crashReportingConfig, in: self.core)
            RUM.enable(with: self.rumConfig, in: self.core)
        }
    }

    /// Asserts that a hang is tracked with no stack trace, with the SDK enabled by `enableSDK`.
    ///
    /// Both enablement orders get their own test rather than being picked at random: only the RUM-first order
    /// proves that the opt-out is read per hang instead of being captured when RUM is enabled, so randomizing
    /// would let that regression pass half of the runs.
    private func assertAppHangIsTrackedWithNoStackTrace(enableSDK: (CrashReporting.Configuration) -> Void) throws {
        // Given (initialize SDK on the main thread)
        enableSDK(CrashReporting.Configuration(appHangBacktraceEnabled: false))

        // When
        mainQueue.sync {
            Thread.sleep(forTimeInterval: hangDuration)
        }

        // Then
        try flushHangsMonitoring()
        let errors = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMErrorEvent.self)
        let appHangError = try XCTUnwrap(errors.first)

        XCTAssertEqual(appHangError.error.message, AppHangsMonitor.Constants.appHangErrorMessage)
        XCTAssertEqual(appHangError.error.type, AppHangsMonitor.Constants.appHangErrorType)
        XCTAssertEqual(appHangError.error.stack, AppHangsMonitor.Constants.appHangStackDisabledErrorMessage)
        XCTAssertEqual(appHangError.error.source, .source)
        XCTAssertNil(appHangError.error.threads, "Threads should be unavailable as App Hang backtraces were disabled")
        XCTAssertNil(appHangError.error.binaryImages, "Binary Images should be unavailable as App Hang backtraces were disabled")
        XCTAssertNil(appHangError.error.wasTruncated, "Truncation flag should be unavailable as App Hang backtraces were disabled")
    }

    func testGivenOnlyRUMEnabled_whenMainThreadHangs_itTracksAppHangWithNoStackTrace() throws {
        // Given
        mainQueue.sync {
            RUM.enable(with: rumConfig, in: core)
        }

        // When
        mainQueue.sync {
            Thread.sleep(forTimeInterval: hangDuration)
        }

        // Then
        try flushHangsMonitoring()
        let errors = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMErrorEvent.self)
        let appHangError = try XCTUnwrap(errors.first)

        XCTAssertEqual(appHangError.error.message, AppHangsMonitor.Constants.appHangErrorMessage)
        XCTAssertEqual(appHangError.error.type, AppHangsMonitor.Constants.appHangErrorType)
        XCTAssertEqual(appHangError.error.stack, AppHangsMonitor.Constants.appHangStackNotAvailableErrorMessage)
        XCTAssertEqual(appHangError.error.source, .source)
        XCTAssertNil(appHangError.error.threads, "Threads should be unavailable as CrashReporting was not enabled")
        XCTAssertNil(appHangError.error.binaryImages,  "Binary Images should be unavailable as CrashReporting was not enabled")
    }

    private func flushHangsMonitoring() throws {
        mainQueue.sync {} // flush the mock main queue (by awaiting the next task after the hang)

        // Flush the watchdog thread (by awaiting on the real main thread), to make sure the thread is done with any hang processing
        // and it is idle:
        let hangObserver = try XCTUnwrap(core.get(feature: RUMFeature.self)?.instrumentation.appHangs)
        hangObserver.flush()
    }
}
