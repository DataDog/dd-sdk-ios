/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMDeviceInfoTests: XCTestCase {
    func testItSetsBrandAndModelAndName() {
        let randomModel: String = .mockRandom()
        let randomName: String = .mockRandom()

        let info = RUMDevice(
            from: .mockWith(name: randomName, model: randomModel),
            telemetry: nil
        )

        XCTAssertEqual(info.brand, "Apple")
        XCTAssertEqual(info.name, randomName)
        XCTAssertEqual(info.model, randomModel)
    }

    func testItInfersDeviceTypeFromDeviceModel() {
        let iPhone = RUMDevice(
            from: .mockWith(model: "iPhone" + String.mockRandom(among: .alphanumerics, length: 2)),
            telemetry: nil
        )
        let iPod = RUMDevice(
            from: .mockWith(model: "iPod" + String.mockRandom(among: .alphanumerics, length: 2)),
            telemetry: nil
        )
        let iPad = RUMDevice(
            from: .mockWith(model: "iPad" + String.mockRandom(among: .alphanumerics, length: 2)),
            telemetry: nil
        )
        let appleTV = RUMDevice(
            from: .mockWith(model: "AppleTV" + String.mockRandom(among: .alphanumerics, length: 2)),
            telemetry: nil
        )
        let unknownDevice = RUMDevice(
            from: .mockWith(model: .mockRandom()),
            telemetry: nil
        )

        XCTAssertEqual(iPhone.type, .mobile)
        XCTAssertEqual(iPod.type, .mobile)
        XCTAssertEqual(iPad.type, .tablet)
        XCTAssertEqual(appleTV.type, .tv)
        XCTAssertEqual(unknownDevice.type, .other)
    }
}
