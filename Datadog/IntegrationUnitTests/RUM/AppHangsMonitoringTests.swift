/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM

/// Test case covering scenarios of App Hangs monitoring in RUM.
class AppHangsMonitoringTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional
    private var rumConfig = RUM.Configuration(applicationID: .mockAny())

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy()
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    func testWhenMainThreadHangsAboveThreshold_itTracksAppHang() throws {
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

        XCTAssertEqual(appHangError.error.message, "App Hang")
        XCTAssertEqual(appHangError.error.type, "AppHang")
        XCTAssertEqual(appHangError.error.source, .source)
        XCTAssertGreaterThanOrEqual(appHangError.date, beforeHang.timeIntervalSince1970.toInt64Milliseconds)
    }
}
