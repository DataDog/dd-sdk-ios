/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import Datadog

class RUMDeviceInfoTests: XCTestCase {
    func testItSetsProperties() {
        let randomModel: String = .mockRandom()
        let randomName: String = .mockRandom()
        let randomArch: String = .mockRandom()

        let info = RUMDevice(
            device: .mockWith(name: randomName, model: randomModel, architecture: randomArch)
        )

        XCTAssertEqual(info.brand, "Apple")
        XCTAssertEqual(info.name, randomName)
        XCTAssertEqual(info.model, randomModel)
        XCTAssertEqual(info.architecture, randomArch)
    }

    func testItInfersDeviceTypeFromDeviceModel() {
        let iPhone = RUMDevice(
            device: .mockWith(model: "iPhone" + String.mockRandom(among: .alphanumerics, length: 2))
        )
        let iPod = RUMDevice(
            device: .mockWith(model: "iPod" + String.mockRandom(among: .alphanumerics, length: 2))
        )
        let iPad = RUMDevice(
            device: .mockWith(model: "iPad" + String.mockRandom(among: .alphanumerics, length: 2))
        )
        let appleTV = RUMDevice(
            device: .mockWith(model: "AppleTV" + String.mockRandom(among: .alphanumerics, length: 2))
        )
        let unknownDevice = RUMDevice(
            device: .mockWith(model: .mockRandom())
        )

        XCTAssertEqual(iPhone.type, .mobile)
        XCTAssertEqual(iPod.type, .mobile)
        XCTAssertEqual(iPad.type, .tablet)
        XCTAssertEqual(appleTV.type, .tv)
        XCTAssertEqual(unknownDevice.type, .other)
    }
}
