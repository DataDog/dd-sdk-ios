/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@testable import DatadogInternal

class DatadogCoreProtocolTests: XCTestCase {
    func testSendMessageExtension() throws {
        // Given
        let receiver = FeatureMessageReceiverMock()
        let core = PassthroughCoreMock(messageReceiver: receiver)

        // When
        core.send(message: .baggage(key: "test", value: "value"))

        // Then
        XCTAssertEqual(
            try receiver.messages.last?.baggage(forKey: "test"), "value", "DatadogCoreProtocol.send(message:) should forward message"
        )
    }

    func testSetBaggageExtension() throws {
        // Given
        let core = PassthroughCoreMock()

        // Then
        core.set(baggage: FeatureBaggage("value"), forKey: "test")
        XCTAssertEqual(
            try core.context.baggages["test"]?.decode(), "value", "DatadogCoreProtocol.set(baggage:) should forward baggage"
        )

        core.set(baggage: nil, forKey: "test")
        XCTAssertNil(core.context.baggages["test"], "DatadogCoreProtocol.set(baggage:) should forward baggage" )

        core.set(baggage: { "value" }, forKey: "test")
        XCTAssertEqual(
            try core.context.baggages["test"]?.decode(), "value", "DatadogCoreProtocol.set(baggage:) should forward baggage"
        )

        core.set(baggage: { nil as String? }, forKey: "test")
        XCTAssertNil(core.context.baggages["test"], "DatadogCoreProtocol.set(baggage:) should forward baggage" )

        core.set(baggage: "value", forKey: "test")
        XCTAssertEqual(
            try core.context.baggages["test"]?.decode(), "value", "DatadogCoreProtocol.set(baggage:) should forward baggage"
        )

        core.set(baggage: nil as String?, forKey: "test")
        XCTAssertNil(core.context.baggages["test"], "DatadogCoreProtocol.set(baggage:) should forward baggage" )
    }
}
