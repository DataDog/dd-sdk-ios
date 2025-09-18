/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@_spi(objc)
@testable import DatadogLogs

class LogsDataModels_objcTests: XCTestCase {
    func testSwiftDDDevice_isEqualToObjCDDDevice() throws {
        // Given
        let swiftDevice: Device = .mockRandom()
        let objcLogEvent = objc_LogEvent(swiftModel: .mockWith(device: swiftDevice))
        let objcDDDevice = objc_LogEventDDDevice(root: objcLogEvent)

        // Then
        XCTAssertEqual(swiftDevice.architecture, objcDDDevice.architecture)
        XCTAssertEqual(swiftDevice.architecture, objcLogEvent.dd.device.architecture)
    }

    func testSwiftDevice_isEqualToObjCDevice() throws {
        // Given
        let swiftDevice: Device = .mockRandom()
        let objcLogEvent = objc_LogEvent(swiftModel: .mockWith(device: swiftDevice))
        let objcDevice = objc_LogEventDevice(root: objcLogEvent)

        // Then
        XCTAssertEqual(swiftDevice.architecture, objcDevice.architecture)
        XCTAssertEqual(swiftDevice.batteryLevel, objcDevice.batteryLevel)
        XCTAssertEqual(swiftDevice.brand, objcDevice.brand)
        XCTAssertEqual(swiftDevice.brightnessLevel, objcDevice.brightnessLevel)
        XCTAssertEqual(swiftDevice.locale, objcDevice.locale)
        XCTAssertEqual(swiftDevice.locales, objcDevice.locales)
        XCTAssertEqual(swiftDevice.model, objcDevice.model)
        XCTAssertEqual(swiftDevice.name, objcDevice.name)
        XCTAssertEqual(swiftDevice.powerSavingMode, objcDevice.powerSavingMode)
        XCTAssertEqual(swiftDevice.timeZone, objcDevice.timeZone)
        XCTAssertEqual(swiftDevice.type, objcDevice.type.toSwift)
    }
}
