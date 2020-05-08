/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DDTracerConfigurationTests: XCTestCase {
    private typealias Configuration = DDTracer.Configuration
    private typealias ResolvedConfiguration = DDTracer.ResolvedConfiguration

    func testDefaultConfiguration() {
        func verify(configuration: Configuration) {
            let resolvedConfiguration = ResolvedConfiguration(tracerConfiguration: configuration)

            XCTAssertEqual(resolvedConfiguration.serviceName, "ios")
        }

        verify(configuration: Configuration())

        var configuration = Configuration()
        configuration.serviceName = nil
        verify(configuration: configuration)
    }

    func testCustomServiceName() {
        func verify(configuration: Configuration) {
            let resolvedConfiguration = ResolvedConfiguration(tracerConfiguration: configuration)

            XCTAssertEqual(resolvedConfiguration.serviceName, "custom")
        }

        verify(configuration: Configuration(serviceName: "custom"))

        var configuration = Configuration()
        configuration.serviceName = "custom"
        verify(configuration: configuration)
    }
}
