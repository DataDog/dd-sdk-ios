/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@testable import DatadogInternal

private final class CoreMock: DatadogCoreProtocol {
    var message: FeatureMessage? = nil
    var baggages: [String: FeatureBaggage] = [:]

    // no-op
    func register<T>(feature: T) throws where T: DatadogFeature { }
    func get<T>(feature type: T.Type) -> T? where T: DatadogFeature { nil }
    func scope(for feature: String) -> FeatureScope? { nil }

    func set(baggage: @escaping () -> FeatureBaggage?, forKey key: String) {
        self.baggages[key] = baggage()
    }

    func send(message: FeatureMessage, else fallback: @escaping () -> Void) {
        self.message = message
    }
}

class DatadogCoreProtocolTests: XCTestCase {
    func testSendMessageExtension() throws {
        // Given
        let core = CoreMock()

        // When
        core.send(message: .baggage(key: "test", value: "value"))

        // Then
        XCTAssertEqual(
            try core.message?.baggage(forKey: "test"), "value", "DatadogCoreProtocol.send(message:) should forward message"
        )
    }

    func testSetBaggageExtension() throws {
        // Given
        let core = CoreMock()

        // Then
        core.set(baggage: FeatureBaggage("value"), forKey: "test")
        XCTAssertEqual(
            try core.baggages["test"]?.decode(), "value", "DatadogCoreProtocol.set(baggage:) should forward baggage"
        )

        core.set(baggage: nil, forKey: "test")
        XCTAssertNil(core.baggages["test"], "DatadogCoreProtocol.set(baggage:) should forward baggage" )

        core.set(baggage: { "value" }, forKey: "test")
        XCTAssertEqual(
            try core.baggages["test"]?.decode(), "value", "DatadogCoreProtocol.set(baggage:) should forward baggage"
        )

        core.set(baggage: { nil as String? }, forKey: "test")
        XCTAssertNil(core.baggages["test"], "DatadogCoreProtocol.set(baggage:) should forward baggage" )

        core.set(baggage: "value", forKey: "test")
        XCTAssertEqual(
            try core.baggages["test"]?.decode(), "value", "DatadogCoreProtocol.set(baggage:) should forward baggage"
        )

        core.set(baggage: nil as String?, forKey: "test")
        XCTAssertNil(core.baggages["test"], "DatadogCoreProtocol.set(baggage:) should forward baggage" )
    }
}
