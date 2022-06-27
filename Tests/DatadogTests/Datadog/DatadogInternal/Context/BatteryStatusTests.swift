/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import UIKit
@testable import Datadog

class BatteryStatusTests: XCTestCase {
    func testWhenInstantiated_itEnablesBatteryMonitoring() {
        let expectation = self.expectation(description: "call configuration block")

        _ = BatteryStatusProvider(
            enableBatteryStatusMonitoring: { expectation.fulfill() },
            resetBatteryStatusMonitoring: {},
            currentBatteryStatus: { .mockAny() }
        )

        waitForExpectations(timeout: 1, handler: nil)
    }

    func testWhenDeinitialized_itResetsBatteryMonitoring() {
        let expectation = self.expectation(description: "call configuration block")

        autoreleasepool {
            _ = BatteryStatusProvider(
                enableBatteryStatusMonitoring: {},
                resetBatteryStatusMonitoring: { expectation.fulfill() },
                currentBatteryStatus: { .mockAny() }
            )
        }

        waitForExpectations(timeout: 1, handler: nil)
    }

    // swiftlint:disable trailing_whitespace
    func testItReturnsCurrentBatteryStatus() {
        let battery = BatteryStatusProvider(
            enableBatteryStatusMonitoring: { },
            resetBatteryStatusMonitoring: {},
            currentBatteryStatus: {
                BatteryStatus(
                    state: .charging,
                    level: 0.5,
                    isLowPowerModeEnabled: false
                )
            }
        )

        XCTAssertEqual(battery.current.state, .charging)
        XCTAssertEqual(battery.current.level, 0.5)
        XCTAssertFalse(battery.current.isLowPowerModeEnabled)
    }

    #if os(iOS)

    private let notificationCenter = NotificationCenter()

    func testWhenRunningOnMobile_itUsesUIDeviceBatteryState() {
        func battery(withState state: UIDevice.BatteryState) -> BatteryStatusProvider {
            return BatteryStatusProvider(
                device: UIDeviceMock(batteryState: state),
                processInfo: ProcessInfoMock(),
                notificationCenter: notificationCenter
            )
        }
        XCTAssertEqual(battery(withState: .full).current.state, .full)
        XCTAssertEqual(battery(withState: .charging).current.state, .charging)
        XCTAssertEqual(battery(withState: .unplugged).current.state, .unplugged)
        XCTAssertEqual(battery(withState: .unknown).current.state, .unknown)
    }

    func testWhenRunningOnMobile_itUsesUIDeviceBatteryLevel() {
        let randomBatteryLevel: Float = .random(in: 0...1)
        let battery = BatteryStatusProvider(
            device: UIDeviceMock(batteryLevel: randomBatteryLevel),
            processInfo: ProcessInfoMock(),
            notificationCenter: notificationCenter
        )
        XCTAssertEqual(battery.current.level, randomBatteryLevel)
    }

    func testGivenInitialLowPowerModeSettingValue_whenSettingChanges_itUpdatesIsLowPowerModeEnabledValue() {
        // Given
        let isLowPowerModeEnabled: Bool = .random()

        let battery = BatteryStatusProvider(
            device: UIDeviceMock(),
            processInfo: ProcessInfoMock(isLowPowerModeEnabled: isLowPowerModeEnabled),
            notificationCenter: notificationCenter
        )

        XCTAssertEqual(battery.current.isLowPowerModeEnabled, isLowPowerModeEnabled)

        // When
        notificationCenter.post(
            name: .NSProcessInfoPowerStateDidChange,
            object: ProcessInfoMock(isLowPowerModeEnabled: !isLowPowerModeEnabled)
        )

        // Then
        let expectation = self.expectation(description: "Update `isLowPowerModeEnabled` in `BatteryStatus`")
        wait(
            until: { battery.current.isLowPowerModeEnabled == !isLowPowerModeEnabled },
            andThenFulfill: expectation
        )
        waitForExpectations(timeout: 0.5, handler: nil)
    }

    func testWhenRunningOnMobile_itTogglesBatteryMonitoring() {
        let device = UIDeviceMock(
            isBatteryMonitoringEnabled: false,
            batteryState: .unplugged
        )
        XCTAssertFalse(device.isBatteryMonitoringEnabled)

        var battery: BatteryStatusProvider? = .init(
            device: device,
            processInfo: ProcessInfoMock(),
            notificationCenter: notificationCenter
        )

        XCTAssertTrue(device.isBatteryMonitoringEnabled)
        XCTAssertEqual(battery?.current.state, .unplugged)

        battery = nil
        XCTAssertFalse(device.isBatteryMonitoringEnabled)
    }

    #elseif os(tvOS)

    func testWhenRunningOnAppleTV_itReportsFullBatteryState() {
        let battery = BatteryStatusProvider()
        XCTAssertEqual(battery.current.level, 1)
        XCTAssertEqual(battery.current.state, .full)
        XCTAssertFalse(battery.current.isLowPowerModeEnabled)
    }

    #endif
}
