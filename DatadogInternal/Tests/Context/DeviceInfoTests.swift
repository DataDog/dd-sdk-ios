/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

class DeviceInfoTests: XCTestCase {
    func testWhenRunningOnMobile_itUsesUIDeviceInfo() {
        let randomUIDeviceModel: String = .mockRandom()
        let randomModel: String = .mockRandom()
        let randomOSName: String = .mockRandom()
        let randomOSVersion: String = .mockRandom()
        let info = DeviceInfo(
            processInfo: ProcessInfoMock(environment: [
                "SIMULATOR_MODEL_IDENTIFIER": randomModel
            ]),
            device: UIDeviceMock(
                model: randomUIDeviceModel,
                systemName: randomOSName,
                systemVersion: randomOSVersion
            )
        )

        XCTAssertEqual(info.brand, "Apple")
        XCTAssertEqual(info.name, randomUIDeviceModel)
        XCTAssertEqual(info.model, "\(randomModel) Simulator")
        XCTAssertEqual(info.osName, randomOSName)
        XCTAssertEqual(info.osVersion, randomOSVersion)
        XCTAssertNotNil(info.osBuildNumber)
    }

    func testDeviceType() {
        // Given
        let iPhone = UIDeviceMock(model: "iPhone14,5", systemName: "iOS")
        let iPod = UIDeviceMock(model: "iPod7,1", systemName: "iOS")
        let iPad = UIDeviceMock(model: "iPad12,1", systemName: "iPadOS")
        let appleTV1 = UIDeviceMock(model: "J305AP", systemName: "tvOS")
        let appleTV2 = UIDeviceMock(model: "AppleTV14,1 Simulator", systemName: "tvOS")
        let other = UIDeviceMock(model: "RealityDevice14,1", systemName: "visionOS")

        // When / Then
        func when(device: UIDeviceMock) -> DeviceInfo {
            return DeviceInfo(processInfo: ProcessInfoMock(), device: device)
        }

        XCTAssertEqual(when(device: iPhone).type, .iPhone)
        XCTAssertEqual(when(device: iPod).type, .iPod)
        XCTAssertEqual(when(device: iPad).type, .iPad)
        XCTAssertEqual(when(device: appleTV1).type, .appleTV)
        XCTAssertEqual(when(device: appleTV2).type, .appleTV)
        XCTAssertEqual(when(device: other).type, .other(modelName: "RealityDevice14,1 Simulator", osName: "visionOS"))
    }
}
