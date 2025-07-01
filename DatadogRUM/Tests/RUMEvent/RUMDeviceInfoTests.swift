/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogRUM

class RUMDeviceInfoTests: XCTestCase {
    func testItSetsProperties() {
        let randomModel: String = .mockRandom()
        let randomName: String = .mockRandom()
        let randomArch: String = .mockRandom()

        let batteryLevel: Double = .mockRandom()
        let brightnessLevel: Double = .mockRandom()
        let powerSavingMode: Bool = .mockRandom()

        let info = RUMDevice(
            device: .mockWith(name: randomName, model: randomModel, architecture: randomArch),
            batteryLevel: batteryLevel,
            brightnessLevel: brightnessLevel,
            powerSavingMode: powerSavingMode,
            localeInfo: .mockWith(locales: ["en"], currentLocale: Locale(identifier: "en"))
        )

        XCTAssertEqual(info.brand, "Apple")
        XCTAssertEqual(info.name, randomName)
        XCTAssertEqual(info.model, randomModel)
        XCTAssertEqual(info.architecture, randomArch)
    }

    func testItInfersDeviceTypeFromDeviceModel() {
        let iPhone = RUMDevice(
            context: .mockWith(device: .mockWith(model: "iPhone" + String.mockRandom(among: .alphanumerics, length: 2)))
        )
        let iPod = RUMDevice(
            context: .mockWith(device: .mockWith(model: "iPod" + String.mockRandom(among: .alphanumerics, length: 2)))
        )
        let iPad = RUMDevice(
            context: .mockWith(device: .mockWith(model: "iPad" + String.mockRandom(among: .alphanumerics, length: 2)))
        )
        let appleTV = RUMDevice(
            context: .mockWith(device: .mockWith(model: "AppleTV" + String.mockRandom(among: .alphanumerics, length: 2)))
        )
        let unknownDevice = RUMDevice(
            context: .mockWith(device: .mockWith(model: .mockRandom()))
        )

        XCTAssertEqual(iPhone.type, .mobile)
        XCTAssertEqual(iPod.type, .mobile)
        XCTAssertEqual(iPad.type, .tablet)
        XCTAssertEqual(appleTV.type, .tv)
        XCTAssertEqual(unknownDevice.type, .other)
    }
}
