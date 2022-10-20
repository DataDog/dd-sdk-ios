/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class MessageBusTests: XCTestCase {
    func testV1MessageBus() throws {
        let expectation = expectation(description: "message received from the bus")
        expectation.expectedFulfillmentCount = 2

        // Given
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            consentProvider: .mockAny(),
            userInfoProvider: .mockAny(),
            performance: .mockAny(),
            httpClient: .mockAny(),
            encryption: nil,
            v1Context: .mockAny(),
            contextProvider: .mockAny()
        )

        defer { temporaryCoreDirectory.delete() }

        let receiver = FeatureMessageReceiverMock(expectation: expectation) { message in
            // Then
            switch message {
            case .custom(let key, let attributes):
                XCTAssertEqual(key, "test")
                XCTAssertEqual(attributes["key"], "value")
            default:
                XCTFail("wrong message case")
            }
        }

        let logging: LoggingFeature = try core.create(
            configuration: .init(
                name: "logs",
                requestBuilder: FeatureRequestBuilderMock(),
                messageReceiver: receiver
            ),
            featureSpecificConfiguration: .mockAny()
        )

        let rum: RUMFeature = try core.create(
            configuration: .init(
                name: "rum",
                requestBuilder: FeatureRequestBuilderMock(),
                messageReceiver: receiver
            ),
            featureSpecificConfiguration: .mockAny()
        )

        core.register(feature: logging)
        core.register(feature: rum)

        // When
        core.send(message: .custom(key: "test", baggage: ["key": "value"]))
        // Then
        waitForExpectations(timeout: 0.5)
    }
}
