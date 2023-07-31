/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogRUM

class RUMMonitorProtocol_InternalTests: XCTestCase {
    func testInternalInterfaceIsAvailableOnMonitor() {
        let monitor: RUMMonitorProtocol

        // When
        monitor = Monitor(
            core: PassthroughCoreMock(),
            dependencies: .mockAny(),
            dateProvider: SystemDateProvider()
        )

        // Then
        XCTAssertIdentical(monitor._internal?.monitor, monitor)
    }

    func testInternalInterfaceIsNotAvailableOnNOPMonitor() {
        let monitor: RUMMonitorProtocol

        // When
        monitor = NOPMonitor()

        // Then
        XCTAssertNil(monitor._internal)
    }
}
