/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogProfiling

final class ProfilingConditionsTests: XCTestCase {
    func testCanProfileApplication_whenAllDefaultConditionsMet() {
        // Given
        let conditions = ProfilingConditions()
        let context: DatadogContext = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            batteryStatus: .mockWith(state: .charging, level: 1.0),
            isLowPowerModeEnabled: false
        )

        // Then
        XCTAssertTrue(conditions.canProfileApplication(with: context))
    }

    func testCannotProfileApplication_whenLowPowerModeEnabled() {
        // Given
        let conditions = ProfilingConditions()
        let context: DatadogContext = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            batteryStatus: .mockWith(state: .full, level: 1.0),
            isLowPowerModeEnabled: true
        )

        // Then
        XCTAssertFalse(conditions.canProfileApplication(with: context))
    }

    func testCannotProfileApplication_whenBatteryBelowMinimumAndUnplugged() {
        // Given
        let conditions = ProfilingConditions()
        let context: DatadogContext = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            batteryStatus: .mockWith(state: .unplugged, level: 0.05),
            isLowPowerModeEnabled: false
        )

        // Then
        XCTAssertFalse(conditions.canProfileApplication(with: context))
    }

    func testCanProfileApplication_whenBatteryBelowMinimumButCharging() {
        // Given
        let conditions = ProfilingConditions()
        let context: DatadogContext = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            batteryStatus: .mockWith(state: .charging, level: 0.05),
            isLowPowerModeEnabled: false
        )

        // Then
        XCTAssertTrue(conditions.canProfileApplication(with: context))
    }

    func testCannotProfileApplication_whenInBackground() {
        // Given
        let conditions = ProfilingConditions()
        let context: DatadogContext = .mockWith(
            applicationStateHistory: .mockAppInBackground(),
            batteryStatus: .mockWith(state: .full, level: 1.0),
            isLowPowerModeEnabled: false
        )

        // Then
        XCTAssertFalse(conditions.canProfileApplication(with: context))
    }

    // Missing battery info should not block profiling (e.g. simulator)
    func testCanProfileApplication_whenBatteryStatusIsMissing() {
        let conditions = ProfilingConditions()

        // Given — battery status not available
        let noStatus: DatadogContext = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            batteryStatus: nil,
            isLowPowerModeEnabled: false
        )
        XCTAssertTrue(conditions.canProfileApplication(with: noStatus))

        // Given — iOS reports level -1.0 when battery monitoring is disabled (e.g. simulator)
        let unknownLevel: DatadogContext = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            batteryStatus: .mockWith(state: .unplugged, level: -1.0),
            isLowPowerModeEnabled: false
        )
        XCTAssertTrue(conditions.canProfileApplication(with: unknownLevel))
    }

    // MARK: - Custom blockers

    func testCanProfileApplication_withNoBlockers() {
        // Given
        let conditions = ProfilingConditions(blockers: [])
        let context: DatadogContext = .mockWith(
            applicationStateHistory: .mockAppInBackground(),
            batteryStatus: .mockWith(state: .unplugged, level: 0.0),
            isLowPowerModeEnabled: true
        )

        // Then
        XCTAssertTrue(conditions.canProfileApplication(with: context))
    }

    func testCanProfileBackgroundApplication_whenNoBackgroundBlocker() {
        // Given
        let conditions = ProfilingConditions(blockers: [.battery, .lowPowerModeOn])
        let context: DatadogContext = .mockWith(
            applicationStateHistory: .mockAppInBackground(),
            batteryStatus: .mockWith(state: .full, level: 1.0),
            isLowPowerModeEnabled: false
        )

        // Then — background state is not checked
        XCTAssertTrue(conditions.canProfileApplication(with: context))
    }

    func testCannotProfileApplication_withCustomMinBatteryLevel() {
        // Given
        let conditions = ProfilingConditions(minBatteryLevel: 0.5)
        let context: DatadogContext = .mockWith(
            applicationStateHistory: .mockAppInForeground(),
            batteryStatus: .mockWith(state: .unplugged, level: 0.4),
            isLowPowerModeEnabled: false
        )

        // Then
        XCTAssertFalse(conditions.canProfileApplication(with: context))
    }
}

#endif // !os(watchOS)
