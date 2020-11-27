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
        case (.us, .us), (.eu, .eu), (.gov, .gov): return true
        case let (.custom(lhsURL), .custom(rhsURL)): return lhsURL == rhsURL
        default: return false
        }
    }
}

extension Datadog.Configuration.TracesEndpoint: Equatable {
    public static func == (_ lhs: Datadog.Configuration.TracesEndpoint, _ rhs: Datadog.Configuration.TracesEndpoint) -> Bool {
        switch (lhs, rhs) {
        case (.us, .us), (.eu, .eu), (.gov, .gov): return true
        case let (.custom(lhsURL), .custom(rhsURL)): return lhsURL == rhsURL
        default: return false
        }
    }
}

/// This tests verify that objc-compatible `DatadogObjc` wrapper properly interacts with`Datadog` public API (swift).
class DDConfigurationTests: XCTestCase {
    func testItFowardsInitializationToSwift() {
        let objcBuilder = DDConfiguration.builder(clientToken: "abc-123", environment: "tests")

        let swiftConfigurationDefault = objcBuilder.build().sdkConfiguration
        XCTAssertEqual(swiftConfigurationDefault.clientToken, "abc-123")
        XCTAssertTrue(swiftConfigurationDefault.loggingEnabled)
        XCTAssertTrue(swiftConfigurationDefault.tracingEnabled)
        XCTAssertEqual(swiftConfigurationDefault.logsEndpoint, .us)
        XCTAssertEqual(swiftConfigurationDefault.tracesEndpoint, .us)
        XCTAssertEqual(swiftConfigurationDefault.environment, "tests")
        XCTAssertNil(swiftConfigurationDefault.serviceName)

        objcBuilder.enableLogging(false)
        let swiftConfigurationLoggingDisabled = objcBuilder.build().sdkConfiguration
        XCTAssertFalse(swiftConfigurationLoggingDisabled.loggingEnabled)

        objcBuilder.enableTracing(false)
        let swiftConfigurationTracingDisabled = objcBuilder.build().sdkConfiguration
        XCTAssertFalse(swiftConfigurationTracingDisabled.tracingEnabled)

        objcBuilder.set(endpoint: .eu())
        let swiftConfigurationEU = objcBuilder.build().sdkConfiguration
        XCTAssertEqual(swiftConfigurationEU.datadogEndpoint, .eu)

        objcBuilder.set(endpoint: .us())
        let swiftConfigurationUS = objcBuilder.build().sdkConfiguration
        XCTAssertEqual(swiftConfigurationUS.datadogEndpoint, .us)

        objcBuilder.set(endpoint: .gov())
        let swiftConfigurationGov = objcBuilder.build().sdkConfiguration
        XCTAssertEqual(swiftConfigurationGov.datadogEndpoint, .gov)

        let customLogsEndpoint = URL(string: "https://api.example.com/v1/logs")!
        let customTracesEndpoint = URL(string: "https://api.example.com/v1/traces")!
        objcBuilder.set(customLogsEndpoint: customLogsEndpoint)
        objcBuilder.set(customTracesEndpoint: customTracesEndpoint)
        let swiftConfigurationCustom = objcBuilder.build().sdkConfiguration
        XCTAssertEqual(swiftConfigurationCustom.customLogsEndpoint, customLogsEndpoint)
        XCTAssertEqual(swiftConfigurationCustom.customTracesEndpoint, customTracesEndpoint)

        objcBuilder.set(serviceName: "service-name")
        let swiftConfigurationServiceName = objcBuilder.build().sdkConfiguration
        XCTAssertEqual(swiftConfigurationServiceName.serviceName, "service-name")

        objcBuilder.track(firstPartyHosts: ["example.com"])
        let swiftConfigurationTracedHosts = objcBuilder.build().sdkConfiguration
        XCTAssertEqual(swiftConfigurationTracedHosts.firstPartyHosts, ["example.com"])
    }
}
