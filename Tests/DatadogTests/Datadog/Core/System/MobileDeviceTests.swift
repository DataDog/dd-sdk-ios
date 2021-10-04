/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import UIKit
@testable import Datadog

class MobileDeviceTests: XCTestCase {
    func testWhenRunningOnMobile_itReturnsDevice() {
        XCTAssertNotNil(MobileDevice.current)
    }

    func testWhenRunningOnMobile_itUsesUIDeviceInfo() {
        let uiDevice = UIDeviceMock(
            model: "model mock",
            systemName: "system name mock",
            systemVersion: "system version mock"
        )
        let mobileDevice = MobileDevice(uiDevice: uiDevice, processInfo: ProcessInfoMock())

        XCTAssertEqual(mobileDevice.model, uiDevice.model)
        XCTAssertEqual(mobileDevice.osName, uiDevice.systemName)
        XCTAssertEqual(mobileDevice.osVersion, uiDevice.systemVersion)
    }

    func testWhenRunningOnMobile_itUsesUIDeviceBatteryState() {
        XCTAssertEqual(
            MobileDevice(uiDevice: UIDeviceMock(batteryState: .full), processInfo: ProcessInfoMock()).currentBatteryStatus().state,
            .full
        )
        XCTAssertEqual(
            MobileDevice(uiDevice: UIDeviceMock(batteryState: .charging), processInfo: ProcessInfoMock()).currentBatteryStatus().state,
            .charging
        )
        XCTAssertEqual(
            MobileDevice(uiDevice: UIDeviceMock(batteryState: .unplugged), processInfo: ProcessInfoMock()).currentBatteryStatus().state,
            .unplugged
        )
        XCTAssertEqual(
            MobileDevice(uiDevice: UIDeviceMock(batteryState: .unknown), processInfo: ProcessInfoMock()).currentBatteryStatus().state,
            .unknown
        )
    }

    func testWhenRunningOnMobile_itUsesUIDeviceBatteryLevel() {
        XCTAssertEqual(
            MobileDevice(uiDevice: UIDeviceMock(batteryLevel: 0.12), processInfo: ProcessInfoMock()).currentBatteryStatus().level,
            0.12
        )
    }

    func testGivenInitialLowPowerModeSettingValue_whenSettingChanges_itUpdatesIsLowPowerModeEnabledValue() {
        // Given
        let isLowPowerModeEnabled: Bool = .random()

        let mobileDevice = MobileDevice(
            uiDevice: UIDeviceMock(),
            processInfo: ProcessInfoMock(isLowPowerModeEnabled: isLowPowerModeEnabled)
        )

        XCTAssertEqual(mobileDevice.currentBatteryStatus().isLowPowerModeEnabled, isLowPowerModeEnabled)

        // When
        NotificationCenter.default.post(
            name: .NSProcessInfoPowerStateDidChange,
            object: ProcessInfoMock(isLowPowerModeEnabled: !isLowPowerModeEnabled)
        )

        // Then
        XCTAssertEqual(mobileDevice.currentBatteryStatus().isLowPowerModeEnabled, !isLowPowerModeEnabled)
    }

    func testWhenRunningOnMobile_itTogglesBatteryMonitoring() {
        let uiDevice = UIDeviceMock(isBatteryMonitoringEnabled: false)
        let mobileDevice = MobileDevice(uiDevice: uiDevice, processInfo: ProcessInfoMock())

        XCTAssertFalse(uiDevice.isBatteryMonitoringEnabled)
        mobileDevice.enableBatteryStatusMonitoring()
        XCTAssertTrue(uiDevice.isBatteryMonitoringEnabled)
        mobileDevice.resetBatteryStatusMonitoring()
        XCTAssertFalse(uiDevice.isBatteryMonitoringEnabled)
    }
}
