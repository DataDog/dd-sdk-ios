/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class BatteryStatusReaderTests: XCTestCase {
#if os(iOS)

    func testWhenRunningOnMobile_itUsesUIDeviceBatteryState() {
        func reader(withState state: UIDevice.BatteryState) -> BatteryStatusReader {
            return BatteryStatusReader(device: UIDeviceMock(batteryState: state))
        }

        var status: BatteryStatus? = nil
        reader(withState: .full).read(to: &status)
        XCTAssertEqual(status?.state, .full)

        reader(withState: .charging).read(to: &status)
        XCTAssertEqual(status?.state, .charging)

        reader(withState: .unplugged).read(to: &status)
        XCTAssertEqual(status?.state, .unplugged)

        reader(withState: .unknown).read(to: &status)
        XCTAssertEqual(status?.state, .unknown)
    }

    func testWhenRunningOnMobile_itUsesUIDeviceBatteryLevel() {
        // Given
        let randomBatteryLevel: Float = .random(in: 0...1)
        let reader = BatteryStatusReader(device: UIDeviceMock(batteryLevel: randomBatteryLevel))
        var status: BatteryStatus? = nil

        // When
        reader.read(to: &status)

        // Then
        XCTAssertEqual(status?.level, randomBatteryLevel)
    }

    func testWhenRunningOnMobile_itTogglesBatteryMonitoring() {
        // Given
        let device = UIDeviceMock(
            isBatteryMonitoringEnabled: false,
            batteryState: .unplugged
        )
        XCTAssertFalse(device.isBatteryMonitoringEnabled)

        var reader: BatteryStatusReader? = BatteryStatusReader(device: device)
        var status: BatteryStatus? = nil

        // When
        reader?.read(to: &status)

        // Then
        XCTAssertTrue(device.isBatteryMonitoringEnabled)
        XCTAssertEqual(status?.state, .unplugged)

        // When
        reader = nil

        // Then
        XCTAssertFalse(device.isBatteryMonitoringEnabled)
    }

    #endif
}
