/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogRUM

final class DeviceInfoTests: XCTestCase {
    func testItSetsProperties() {
        let randomModel: String = .mockRandom()
        let randomName: String = .mockRandom()
        let randomArch: String = .mockRandom()

        let info: Device = .mockWith(architecture: randomArch, model: randomModel, name: randomName)

        XCTAssertEqual(info.brand, "Apple")
        XCTAssertEqual(info.name, randomName)
        XCTAssertEqual(info.model, randomModel)
        XCTAssertEqual(info.architecture, randomArch)
    }

    func testItInfersDeviceTypeFromDeviceModel() {
        let iPhone: DeviceInfo = .mockWith(model: "iPhone" + String.mockRandom(among: .alphanumerics, length: 2))
        let iPod: DeviceInfo = .mockWith(model: "iPod" + String.mockRandom(among: .alphanumerics, length: 2))
        let iPad: DeviceInfo = .mockWith(model: "iPad" + String.mockRandom(among: .alphanumerics, length: 2))
        let appleTV: DeviceInfo = .mockWith(model: "AppleTV" + String.mockRandom(among: .alphanumerics, length: 2))
        let unknownDevice: DeviceInfo = .mockWith(model: .mockRandom())

        XCTAssertEqual(iPhone.type.normalizedDeviceType, .mobile)
        XCTAssertEqual(iPod.type.normalizedDeviceType, .mobile)
        XCTAssertEqual(iPad.type.normalizedDeviceType, .tablet)
        XCTAssertEqual(appleTV.type.normalizedDeviceType, .tv)
        XCTAssertEqual(unknownDevice.type.normalizedDeviceType, .other)
    }
}
