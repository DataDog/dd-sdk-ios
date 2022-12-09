/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog
@testable import DatadogObjc

class DDLoggerBuilderTests: XCTestCase {
    func testItForwardsConfigurationToSwift() {
        let swiftBuilder = Logger.builder
        let objcBuilder = DDLoggerBuilder(sdkBuilder: swiftBuilder)
        objcBuilder.set(loggerName: "logger-name")
        objcBuilder.set(serviceName: "service-name")
        objcBuilder.sendNetworkInfo(true)
        objcBuilder.sendLogsToDatadog(false)
        objcBuilder.printLogsToConsole(true)

        XCTAssertEqual(swiftBuilder.loggerName, "logger-name")
        XCTAssertEqual(swiftBuilder.serviceName, "service-name")
        XCTAssertTrue(swiftBuilder.sendNetworkInfo)
        XCTAssertFalse(swiftBuilder.sendLogsToDatadog)
        XCTAssertNotNil(swiftBuilder.consoleLogFormat)
    }
}
