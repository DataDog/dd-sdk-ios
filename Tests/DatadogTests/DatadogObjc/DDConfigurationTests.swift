/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import XCTest
@testable import Datadog
@testable import DatadogObjc

extension Datadog.Configuration.LogsEndpoint: Equatable {
    public static func == (_ lhs: Datadog.Configuration.LogsEndpoint, _ rhs: Datadog.Configuration.LogsEndpoint) -> Bool {
        switch (lhs, rhs) {
        case (.us, .us): return true
        case (.eu, .eu): return true
        case let (.custom(lhsURL), .custom(rhsURL)): return lhsURL == rhsURL
        default: return false
        }
    }
}

/// This tests verify that objc-compatible `DatadogObjc` wrapper properly interacts with`Datadog` public API (swift).
class DDConfigurationTests: XCTestCase {
    func testItFowardsInitializationToSwift() {
        let objcBuilder = DDConfiguration.builder(clientToken: "abc-123")

        let swiftConfigurationDefault = objcBuilder.build().sdkConfiguration
        XCTAssertEqual(swiftConfigurationDefault.clientToken, "abc-123")
        XCTAssertEqual(swiftConfigurationDefault.logsEndpoint, .us)

        objcBuilder.set(endpoint: .eu())
        let swiftConfigurationEU = objcBuilder.build().sdkConfiguration
        XCTAssertEqual(swiftConfigurationEU.logsEndpoint, .eu)

        objcBuilder.set(endpoint: .us())
        let swiftConfigurationUS = objcBuilder.build().sdkConfiguration
        XCTAssertEqual(swiftConfigurationUS.logsEndpoint, .us)

        objcBuilder.set(endpoint: .custom(url: "https://api.example.com/v1/logs"))
        let swiftConfigurationCustom = objcBuilder.build().sdkConfiguration
        XCTAssertEqual(swiftConfigurationCustom.logsEndpoint, .custom(url: "https://api.example.com/v1/logs"))
    }
}
