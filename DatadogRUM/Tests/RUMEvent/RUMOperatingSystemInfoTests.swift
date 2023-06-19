/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogRUM

class RUMOperatingSystemInfoTests: XCTestCase {
    func testItSetsOSNameAndVersion() {
        let randomOSName: String = .mockRandom()
        let randomOSVersion: String = .mockRandom()
        let randomOSBuild: String = .mockRandom()

        let info = RUMOperatingSystem(
            device: .mockWith(
                osName: randomOSName,
                osVersion: randomOSVersion,
                osBuildNumber: randomOSBuild
            )
        )

        XCTAssertEqual(info.name, randomOSName)
        XCTAssertEqual(info.version, randomOSVersion)
        XCTAssertEqual(info.build, randomOSBuild)
    }

    func testItInfersOSMajorVersion() {
        var info = RUMOperatingSystem(device: .mockWith(osVersion: "15.4.1"))
        XCTAssertEqual(info.versionMajor, "15")

        info = RUMOperatingSystem(device: .mockWith(osVersion: "1.4"))
        XCTAssertEqual(info.versionMajor, "1")

        info = RUMOperatingSystem(device: .mockWith(osVersion: "1"))
        XCTAssertEqual(info.versionMajor, "1")

        info = RUMOperatingSystem(device: .mockWith(osVersion: "0.1.2-beta1"))
        XCTAssertEqual(info.versionMajor, "0")

        info = RUMOperatingSystem(device: .mockWith(osVersion: "invalid_version"))
        XCTAssertEqual(info.versionMajor, "invalid_version")
    }
}
