/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import UIKit

@testable import Datadog

class DeviceInfoTests: XCTestCase {
    func testWhenRunningOnMobile_itUsesUIDeviceInfo() {
        let randomUIDeviceModel: String = .mockRandom()
        let randomModel: String = .mockRandom()
        let randomOSName: String = .mockRandom()
        let randomOSVersion: String = .mockRandom()
        let randomArchitecutre: String = .mockRandom()

        let info = DeviceInfo(
            model: randomModel,
            device: UIDeviceMock(
                model: randomUIDeviceModel,
                systemName: randomOSName,
                systemVersion: randomOSVersion
            ),
            architecture: randomArchitecutre
        )

        XCTAssertEqual(info.brand, "Apple")
        XCTAssertEqual(info.name, randomUIDeviceModel)
        XCTAssertEqual(info.model, randomModel)
        XCTAssertEqual(info.osName, randomOSName)
        XCTAssertEqual(info.osVersion, randomOSVersion)
        XCTAssertEqual(info.architecture, randomArchitecutre)
    }
}
