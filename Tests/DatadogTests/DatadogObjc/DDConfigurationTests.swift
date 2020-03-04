/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import XCTest
@testable import Datadog
@testable import DatadogObjc

/// This tests verify that objc-compatible `DatadogObjc` wrapper properly interacts with`Datadog` public API (swift).
class DDConfigurationTests: XCTestCase {
    // MARK: - Customizing logs endpoint

    private let swiftEndpoints: [Datadog.Configuration.LogsEndpoint] = [
        .eu, .us, .custom(url: "https://api.example.com/v1/logs")
    ]
    private let objcEndpoints: [DDLogsEndpoint] = [
        .eu(), .us(), .custom(url: "https://api.example.com/v1/logs")
    ]

    func testItForwardsLogsEndpointToSwift() {
        zip(swiftEndpoints, objcEndpoints).forEach { swiftEndpoint, objcEndpoint in
            let objcBuilder = DDConfiguration.builder(clientToken: "abc-123")
            objcBuilder.set(endpoint: objcEndpoint)
            let objcConfiguration = objcBuilder.build()

            let expected = Datadog.Configuration
                .builderUsing(clientToken: "abc-123")
                .set(logsEndpoint: swiftEndpoint)
                .build()

            XCTAssertEqual(objcConfiguration.sdkConfiguration.logsUploadURL?.url, expected.logsUploadURL?.url)
        }
    }
}
