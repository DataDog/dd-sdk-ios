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

    override func setUp() {
        rumConfig.defaultAppHangThreshold = 0.5
        core = DatadogCoreProxy()
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
    }

    func testWhenMainThreadIsHangedInitially_itTracksAppHangError() throws {
        // Given
        RUM.enable(with: rumConfig, in: core)

        // When
        let hangDuration = rumConfig.defaultAppHangThreshold * 1.25
        Thread.sleep(forTimeInterval: hangDuration) // hang right after SDK is initialized

        // Then
        try flushHangsMonitoring()
        let errors = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMErrorEvent.self)
        let appHangError = try XCTUnwrap(errors.first)

        XCTAssertEqual(appHangError.error.message, AppHangsObserver.Constants.appHangErrorMessage)
        XCTAssertEqual(appHangError.error.type, AppHangsObserver.Constants.appHangErrorType)
    }

    func testWhenMainThreadIsHangedAfterInit_itTracksAppHangError() throws {
        // Given
        RUM.enable(with: rumConfig, in: core)

        // When
        let hangDuration = rumConfig.defaultAppHangThreshold * 1.25
        let hangEnded = expectation(description: "Await hang end")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { // 0.5 s after init
            Thread.sleep(forTimeInterval: hangDuration)
            hangEnded.fulfill()
        }
        wait(for: [hangEnded], timeout: 2)

        // Then
        try flushHangsMonitoring()
        let errors = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMErrorEvent.self)
        let appHangError = try XCTUnwrap(errors.first)

        XCTAssertEqual(appHangError.error.message, AppHangsObserver.Constants.appHangErrorMessage)
        XCTAssertEqual(appHangError.error.type, AppHangsObserver.Constants.appHangErrorType)
    }

    func testGivenRUMAndCrashReportingEnabled_whenMainThreadHangs_thenAppHangErrorIncludesStackTrace() throws {
        // Given (no matter of RUM or CR initialization order)
        oneOf([
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
        let hangDuration = rumConfig.defaultAppHangThreshold * 1.25
        Thread.sleep(forTimeInterval: hangDuration) // hang the app

        // Then
        try flushHangsMonitoring()
        let appHangError = try XCTUnwrap(core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMErrorEvent.self).first)
        let mainThreadStack = try XCTUnwrap(appHangError.error.stack)

        XCTAssertEqual(appHangError.error.message, AppHangsObserver.Constants.appHangErrorMessage)
        XCTAssertEqual(appHangError.error.type, AppHangsObserver.Constants.appHangErrorType)
        XCTAssertTrue(mainThreadStack.contains(uiKitLibraryName), "Main thread stack should include UIKit symbols")
        XCTAssertEqual(appHangError.error.source, .source)
        XCTAssertNotNil(appHangError.error.threads, "Other threads should be available")
        XCTAssertNotNil(appHangError.error.binaryImages,  "Binary Images should be available for symbolication")
    }

    func testGivenOnlyRUMEnabled_whenMainThreadHangs_itTracksAppHangWithNoStackTrace() throws {
        // Given
        RUM.enable(with: rumConfig, in: core)

        // When
        let hangDuration = rumConfig.defaultAppHangThreshold * 1.25
        Thread.sleep(forTimeInterval: hangDuration) // hang the app

        // Then
        try flushHangsMonitoring()
        let errors = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMErrorEvent.self)
        let appHangError = try XCTUnwrap(errors.first)

        XCTAssertEqual(appHangError.error.message, AppHangsObserver.Constants.appHangErrorMessage)
        XCTAssertEqual(appHangError.error.type, AppHangsObserver.Constants.appHangErrorType)
        XCTAssertEqual(appHangError.error.stack, AppHangsObserver.Constants.appHangNoStackErrorMessage)
        XCTAssertEqual(appHangError.error.source, .source)
        XCTAssertNil(appHangError.error.threads, "Threads should be unavailable as CrashReporting was not enabled")
        XCTAssertNil(appHangError.error.binaryImages,  "Binary Images should be unavailable as CrashReporting was not enabled")
    }

    private func flushHangsMonitoring() throws {
        let hangObserver = try XCTUnwrap(core.get(feature: RUMFeature.self)?.instrumentation.appHangs)
        let expectation = self.expectation(description: "Flush AppHangObserver")
        DispatchQueue.main.async {
            hangObserver.flush() // flush from async task on main queue, so we're sure watchdog thread finished processing previous hang
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        RUMMonitor.shared(in: core).dd.flush() // flush also RUMMonitor so it ends processing hangs flushed from `hangObserver`
    }
}
