/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DatadogConfigurationBuilderTests: XCTestCase {
    func testDefaultBuilder() {
        let configuration = Datadog.Configuration
            .builderUsing(clientToken: "abc-123", environment: "tests")
            .build()

        let rumConfiguration = Datadog.Configuration
            .builderUsing(rumApplicationID: "rum-app-id", clientToken: "abc-123", environment: "tests")
            .build()

        XCTAssertFalse(configuration.rumEnabled)
        XCTAssertTrue(rumConfiguration.rumEnabled)

        XCTAssertNil(configuration.rumApplicationID)
        XCTAssertEqual(rumConfiguration.rumApplicationID, "rum-app-id")

        [configuration, rumConfiguration].forEach { configuration in
            XCTAssertEqual(configuration.clientToken, "abc-123")
            XCTAssertEqual(configuration.environment, "tests")
            XCTAssertTrue(configuration.loggingEnabled)
            XCTAssertTrue(configuration.tracingEnabled)
            XCTAssertEqual(configuration.logsEndpoint.url, "https://mobile-http-intake.logs.datadoghq.com/v1/input/")
            XCTAssertEqual(configuration.tracesEndpoint.url, "https://public-trace-http-intake.logs.datadoghq.com/v1/input/")
            XCTAssertEqual(configuration.rumEndpoint.url, "https://rum-http-intake.logs.datadoghq.com/v1/input/")
            XCTAssertNil(configuration.serviceName)
            XCTAssertEqual(configuration.tracedHosts, [])
            XCTAssertEqual(configuration.rumSessionsSamplingRate, 100.0)
        }
    }

    func testCustomizedBuilder() {
        func customized(_ builder: Datadog.Configuration.Builder) -> Datadog.Configuration.Builder {
            builder
                .set(serviceName: "service-name")
                .enableLogging(false)
                .enableTracing(false)
                .enableRUM(false)
                .set(logsEndpoint: .eu)
                .set(tracesEndpoint: .eu)
                .set(rumEndpoint: .eu)
                .set(tracedHosts: ["example.com"])
                .set(rumSessionsSamplingRate: 42.5)
        }

        let defaultBuilder = Datadog.Configuration
            .builderUsing(clientToken: "abc-123", environment: "tests")
        let defaultRUMBuilder = Datadog.Configuration
            .builderUsing(rumApplicationID: "rum-app-id", clientToken: "abc-123", environment: "tests")

        let configuration = customized(defaultBuilder).build()
        let rumConfiguration = customized(defaultRUMBuilder).build()

        XCTAssertNil(configuration.rumApplicationID)
        XCTAssertEqual(rumConfiguration.rumApplicationID, "rum-app-id")

        [configuration, rumConfiguration].forEach { configuration in
            XCTAssertEqual(configuration.clientToken, "abc-123")
            XCTAssertEqual(configuration.environment, "tests")
            XCTAssertEqual(configuration.serviceName, "service-name")
            XCTAssertFalse(configuration.loggingEnabled)
            XCTAssertFalse(configuration.tracingEnabled)
            XCTAssertFalse(configuration.rumEnabled)
            XCTAssertEqual(configuration.logsEndpoint.url, "https://mobile-http-intake.logs.datadoghq.eu/v1/input/")
            XCTAssertEqual(configuration.tracesEndpoint.url, "https://public-trace-http-intake.logs.datadoghq.eu/v1/input/")
            XCTAssertEqual(configuration.rumEndpoint.url, "https://rum-http-intake.logs.datadoghq.eu/v1/input/")
            XCTAssertEqual(configuration.tracedHosts, ["example.com"])
            XCTAssertEqual(configuration.rumSessionsSamplingRate, 42.5)
        }
    }
}
