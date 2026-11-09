/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

final class SuddenTerminationHoldTests: XCTestCase {
    private let control = SuddenTerminationControlMock()

    func testWhenHeldRepeatedly_itDisablesSuddenTerminationOnce() {
        // Given
        let hold = SuddenTerminationHold(control: control)

        // When
        hold.isHeld = true
        hold.isHeld = true

        // Then
        XCTAssertEqual(control.disableCount, 1)
    }

    func testWhenReleased_itEnablesSuddenTermination() {
        // Given
        let hold = SuddenTerminationHold(control: control)
        hold.isHeld = true

        // When
        hold.isHeld = false
        hold.isHeld = false

        // Then
        XCTAssertEqual(control.disableCount, 0)
    }

    func testWhenDeallocatedWhileHeld_itEnablesSuddenTermination() {
        // Given
        var hold: SuddenTerminationHold? = SuddenTerminationHold(control: control)
        hold?.isHeld = true

        // When
        hold = nil

        // Then
        XCTAssertEqual(control.disableCount, 0)
    }

    func testWhenDeallocatedWithoutHolding_itLeavesSuddenTerminationUnchanged() {
        // Given
        var hold: SuddenTerminationHold? = SuddenTerminationHold(control: control)

        // When
        hold = nil

        // Then
        XCTAssertEqual(control.disableCount, 0)
    }
}
