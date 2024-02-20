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
        core = DatadogCoreProxy()
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
    }

    func testGivenRUMEnabledButCrashReportingNot_whenMainThreadHangs_itTracksAppHangWithNoStack() throws {
        let mainQueue = DispatchQueue(label: "main-queue", qos: .userInteractive)
        rumConfig.mainQueue = mainQueue

        // Given
        RUM.enable(with: rumConfig, in: core)

        // When
        let beforeHang = Date()
        mainQueue.sync {
            Thread.sleep(forTimeInterval: self.rumConfig.defaultAppHangThreshold * 1.5)
        }

        // Then
        Thread.sleep(forTimeInterval: 0.5) // wait to make sure watchdog thread completes hang tracking
        RUMMonitor.shared(in: core).dd.flush() // flush RUM monitor to await hang processing

        let errors = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMErrorEvent.self)
        let appHangError = try XCTUnwrap(errors.first)

        XCTAssertEqual(appHangError.error.message, AppHangsObserver.Constants.appHangErrorMessage)
        XCTAssertEqual(appHangError.error.type, AppHangsObserver.Constants.appHangErrorType)
        XCTAssertEqual(appHangError.error.stack, AppHangsObserver.Constants.appHangNoStackErrorMessage)
        XCTAssertEqual(appHangError.error.source, .source)
        XCTAssertNil(appHangError.error.threads, "Threads should be unavailable as CrashReporting was not enabled")
        XCTAssertNil(appHangError.error.binaryImages,  "Binary Images should be unavailable as CrashReporting was not enabled")
        XCTAssertGreaterThanOrEqual(appHangError.date, beforeHang.timeIntervalSince1970.toInt64Milliseconds)
    }

    func testGivenRUMAndCrashReportingEnabled_whenMainThreadHangs_itTracksAppHangWithMainThreadStack() throws {
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
        let awaitMainThreadHang = expectation(description: "Wait until hang ends")
        DispatchQueue.main.async {
            Thread.sleep(forTimeInterval: hangDuration) // hang the main thread
            DispatchQueue.main.async { awaitMainThreadHang.fulfill() } // hang ended, ready to run test assertions
        }
        waitForExpectations(timeout: rumConfig.defaultAppHangThreshold * 5)

        // Then
        RUMMonitor.shared(in: core).dd.flush() // flush RUM monitor to await hang processing

        let appHangError = try XCTUnwrap(core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMErrorEvent.self).first)
        let mainThreadStack = try XCTUnwrap(appHangError.error.stack)

        XCTAssertEqual(appHangError.error.message, AppHangsObserver.Constants.appHangErrorMessage)
        XCTAssertEqual(appHangError.error.type, AppHangsObserver.Constants.appHangErrorType)
        XCTAssertTrue(mainThreadStack.contains(uiKitLibraryName), "Main thread stack should include UIKit symbols")
        XCTAssertEqual(appHangError.error.source, .source)
        XCTAssertNotNil(appHangError.error.threads, "Other threads should be available")
        XCTAssertNotNil(appHangError.error.binaryImages,  "Binary Images should be available for symbolication")
    }
}
