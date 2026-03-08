/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogCore

class LowPowerModeSourceTests: XCTestCase {
    private let notificationCenter = NotificationCenter()

    func testGivenInitialLowPowerModeSettingValue_whenSettingChanges_itUpdatesIsLowPowerModeEnabledValue() async {
        // Given
        let isLowPowerModeEnabled: Bool = .random()
        let source = LowPowerModeSource(
            notificationCenter: notificationCenter,
            processInfo: ProcessInfoMock(isLowPowerModeEnabled: isLowPowerModeEnabled)
        )

        XCTAssertEqual(source.initialValue, isLowPowerModeEnabled)

        // When
        var iterator = source.values.makeAsyncIterator()

        notificationCenter.post(
            name: .NSProcessInfoPowerStateDidChange,
            object: ProcessInfoMock(isLowPowerModeEnabled: !isLowPowerModeEnabled)
        )

        // Then
        let value = await iterator.next()
        XCTAssertEqual(value, !isLowPowerModeEnabled)
    }
}
