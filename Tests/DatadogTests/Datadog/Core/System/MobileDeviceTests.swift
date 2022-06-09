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
        let randomUIDeviceModel: String = .mockRandom()
        let randomModel: String = .mockRandom()
        let randomOSName: String = .mockRandom()
        let randomOSVersion: String = .mockRandom()

        let uiDevice = UIDeviceMock(
            model: randomUIDeviceModel,
            systemName: randomOSName,
            systemVersion: randomOSVersion
        )
        let mobileDevice = MobileDevice(
            model: randomModel,
            uiDevice: uiDevice,
            processInfo: ProcessInfoMock(),
            notificationCenter: notificationCenter
        )

        XCTAssertEqual(mobileDevice.name, randomUIDeviceModel)
        XCTAssertEqual(mobileDevice.model, randomModel)
        XCTAssertEqual(mobileDevice.osName, randomOSName)
        XCTAssertEqual(mobileDevice.osVersion, randomOSVersion)
    }

    #if os(iOS)

    func testWhenRunningOnMobile_itUsesUIDeviceBatteryState() {
        func mobileDevice(withBatteryState bateryState: UIDevice.BatteryState) -> MobileDevice {
            return MobileDevice(
                model: .mockAny(),
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
            model: .mockAny(),
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
            model: .mockAny(),
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
        let mobileDevice = MobileDevice(
            model: .mockAny(),
            uiDevice: uiDevice,
            processInfo: ProcessInfoMock(),
            notificationCenter: notificationCenter
        )

        XCTAssertFalse(uiDevice.isBatteryMonitoringEnabled)
        mobileDevice.enableBatteryStatusMonitoring()
        XCTAssertTrue(uiDevice.isBatteryMonitoringEnabled)
        mobileDevice.resetBatteryStatusMonitoring()
        XCTAssertFalse(uiDevice.isBatteryMonitoringEnabled)
    }

    #elseif os(tvOS)

    func testWhenRunningOnAppleTV_itReportsFullBatteryState() {
        let device = MobileDevice()
        XCTAssertEqual(device.currentBatteryStatus().level, 1)
        XCTAssertEqual(device.currentBatteryStatus().state, .full)
        XCTAssertFalse(device.currentBatteryStatus().isLowPowerModeEnabled)
    }

    #endif
}
