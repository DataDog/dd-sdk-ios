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
    func testDefaultBuilderFowardsInitializationToSwift() throws {
        let objcBuilder = DDConfiguration.builder(clientToken: "abc-123", environment: "tests")
        let objcRUMBuilder = DDConfiguration.builder(rumApplicationID: "rum-app-id", clientToken: "abc-123", environment: "tests")

        let swiftConfiguration = objcBuilder.build().sdkConfiguration
        let swiftConfigurationRUM = objcRUMBuilder.build().sdkConfiguration

        XCTAssertFalse(swiftConfiguration.rumEnabled)
        XCTAssertTrue(swiftConfigurationRUM.rumEnabled)

        XCTAssertNil(swiftConfiguration.rumApplicationID)
        XCTAssertEqual(swiftConfigurationRUM.rumApplicationID, "rum-app-id")

        [swiftConfiguration, swiftConfigurationRUM].forEach { configuration in
            XCTAssertEqual(configuration.clientToken, "abc-123")
            XCTAssertTrue(configuration.loggingEnabled)
            XCTAssertTrue(configuration.tracingEnabled)
            XCTAssertEqual(configuration.logsEndpoint, .us)
            XCTAssertEqual(configuration.tracesEndpoint, .us)
            XCTAssertEqual(configuration.rumEndpoint, .us)
            XCTAssertEqual(configuration.environment, "tests")
            XCTAssertNil(configuration.serviceName)
            XCTAssertNil(configuration.firstPartyHosts)
            XCTAssertEqual(configuration.rumSessionsSamplingRate, 100.0)
            XCTAssertNil(configuration.rumUIKitViewsPredicate)
            XCTAssertFalse(configuration.rumUIKitActionsTrackingEnabled)
            XCTAssertEqual(configuration.batchSize, .medium)
            XCTAssertEqual(configuration.uploadFrequency, .average)
        }
    }

    func testCustomizedBuilderFowardsInitializationToSwift() throws {
        let objcBuilder = [
            DDConfiguration.builder(clientToken: "abc-123", environment: "tests"),
            DDConfiguration.builder(rumApplicationID: "rum-app-id", clientToken: "abc-123", environment: "tests")
        ].randomElement()!

        objcBuilder.enableLogging(false)
        XCTAssertFalse(objcBuilder.build().sdkConfiguration.loggingEnabled)

        objcBuilder.enableTracing(false)
        XCTAssertFalse(objcBuilder.build().sdkConfiguration.tracingEnabled)

        objcBuilder.enableRUM(false)
        XCTAssertFalse(objcBuilder.build().sdkConfiguration.rumEnabled)

        objcBuilder.set(endpoint: .eu())
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.datadogEndpoint, .eu)

        objcBuilder.set(endpoint: .us())
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.datadogEndpoint, .us)

        objcBuilder.set(endpoint: .gov())
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.datadogEndpoint, .gov)

        let customLogsEndpoint = URL(string: "https://api.example.com/v1/logs")!
        objcBuilder.set(customLogsEndpoint: customLogsEndpoint)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.customLogsEndpoint, customLogsEndpoint)

        let customTracesEndpoint = URL(string: "https://api.example.com/v1/traces")!
        objcBuilder.set(customTracesEndpoint: customTracesEndpoint)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.customTracesEndpoint, customTracesEndpoint)

        let customRUMEndpoint = URL(string: "https://api.example.com/v1/rum")!
        objcBuilder.set(customRUMEndpoint: customRUMEndpoint)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.customRUMEndpoint, customRUMEndpoint)

        objcBuilder.set(serviceName: "service-name")
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.serviceName, "service-name")

        objcBuilder.track(firstPartyHosts: ["example.com"])
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.firstPartyHosts, ["example.com"])

        objcBuilder.trackUIKitActions()
        XCTAssertTrue(objcBuilder.build().sdkConfiguration.rumUIKitActionsTrackingEnabled)

        objcBuilder.trackUIKitRUMViews()
        XCTAssertTrue(objcBuilder.build().sdkConfiguration.rumUIKitViewsPredicate is DefaultUIKitRUMViewsPredicate)

        class ObjCPredicate: DDUIKitRUMViewsPredicate {
            func rumView(for viewController: UIViewController) -> DDRUMView? { nil }
        }
        let predicate = ObjCPredicate()
        objcBuilder.trackUIKitRUMViews(using: predicate)
        XCTAssertTrue((objcBuilder.build().sdkConfiguration.rumUIKitViewsPredicate as? UIKitRUMViewsPredicateBridge)?.objcPredicate === predicate)

        objcBuilder.set(rumSessionsSamplingRate: 42.5)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.rumSessionsSamplingRate, 42.5)

        objcBuilder.set(batchSize: .small)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.batchSize, .small)

        objcBuilder.set(batchSize: .large)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.batchSize, .large)

        objcBuilder.set(uploadFrequency: .frequent)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.uploadFrequency, .frequent)

        objcBuilder.set(uploadFrequency: .rare)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.uploadFrequency, .rare)
    }
}
