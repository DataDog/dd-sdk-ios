/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import UIKit
@testable import Datadog

class MobileDeviceTests: XCTestCase {
    private let notificationCenter = NotificationCenter()

    func testWhenRunningOnMobile_itUsesUIDeviceInfo() {
        let uiDevice = UIDeviceMock(
            model: "model mock",
            systemName: "system name mock",
            systemVersion: "system version mock"
        )
        let mobileDevice = MobileDevice(uiDevice: uiDevice, processInfo: ProcessInfoMock(), notificationCenter: notificationCenter)

        XCTAssertEqual(mobileDevice.model, uiDevice.model)
        XCTAssertEqual(mobileDevice.osName, uiDevice.systemName)
        XCTAssertEqual(mobileDevice.osVersion, uiDevice.systemVersion)
    }

    #if os(iOS)
    func testWhenRunningOnMobile_itUsesUIDeviceBatteryState() {
        func mobileDevice(withBatteryState bateryState: UIDevice.BatteryState) -> MobileDevice {
            return MobileDevice(
                uiDevice: UIDeviceMock(batteryState: bateryState),
                processInfo: ProcessInfoMock(),
                notificationCenter: notificationCenter
            )
        }
        XCTAssertEqual(mobileDevice(withBatteryState: .full).currentBatteryStatus().state, .full)
        XCTAssertEqual(mobileDevice(withBatteryState: .charging).currentBatteryStatus().state, .charging)
        XCTAssertEqual(mobileDevice(withBatteryState: .unplugged).currentBatteryStatus().state, .unplugged)
        XCTAssertEqual(mobileDevice(withBatteryState: .unknown).currentBatteryStatus().state, .unknown)
    }

    func testWhenRunningOnMobile_itUsesUIDeviceBatteryLevel() {
        let randomBatteryLevel: Float = .random(in: 0...1)
        let mobileDevice = MobileDevice(
            uiDevice: UIDeviceMock(batteryLevel: randomBatteryLevel),
            processInfo: ProcessInfoMock(),
            notificationCenter: notificationCenter
        )
        XCTAssertEqual(mobileDevice.currentBatteryStatus().level, randomBatteryLevel)
    }

    func testGivenInitialLowPowerModeSettingValue_whenSettingChanges_itUpdatesIsLowPowerModeEnabledValue() {
        // Given
        let isLowPowerModeEnabled: Bool = .random()

        let mobileDevice = MobileDevice(
            uiDevice: UIDeviceMock(),
            processInfo: ProcessInfoMock(isLowPowerModeEnabled: isLowPowerModeEnabled),
            notificationCenter: notificationCenter
        )

        XCTAssertEqual(mobileDevice.currentBatteryStatus().isLowPowerModeEnabled, isLowPowerModeEnabled)

        // When
        notificationCenter.post(
            name: .NSProcessInfoPowerStateDidChange,
            object: ProcessInfoMock(isLowPowerModeEnabled: !isLowPowerModeEnabled)
        )

        // Then
        let expectation = self.expectation(description: "Update `isLowPowerModeEnabled` in `BatteryStatus`")
        wait(
            until: { mobileDevice.currentBatteryStatus().isLowPowerModeEnabled == !isLowPowerModeEnabled },
            andThenFulfill: expectation
        )
        waitForExpectations(timeout: 0.5, handler: nil)
    }

    func testWhenRunningOnMobile_itTogglesBatteryMonitoring() {
        let uiDevice = UIDeviceMock(isBatteryMonitoringEnabled: false)
        let mobileDevice = MobileDevice(uiDevice: uiDevice, processInfo: ProcessInfoMock(), notificationCenter: notificationCenter)

        XCTAssertFalse(uiDevice.isBatteryMonitoringEnabled)
        mobileDevice.enableBatteryStatusMonitoring()
        XCTAssertTrue(uiDevice.isBatteryMonitoringEnabled)
        mobileDevice.resetBatteryStatusMonitoring()
        XCTAssertFalse(uiDevice.isBatteryMonitoringEnabled)
    }
    #endif
}
