/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog
@testable import DatadogObjc

class DDTracerConfigurationTests: XCTestCase {
    func testItForwardsConfigurationToSwift() {
        let objcConfiguration = DDTracerConfiguration()
        objcConfiguration.set(serviceName: "service-name")
        objcConfiguration.sendNetworkInfo(true)

        let swiftConfiguration = objcConfiguration.swiftConfiguration
        XCTAssertEqual(swiftConfiguration.serviceName, "service-name")
        XCTAssertTrue(swiftConfiguration.sendNetworkInfo)
    }
}
