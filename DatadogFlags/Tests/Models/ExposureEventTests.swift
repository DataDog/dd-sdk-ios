/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@_spi(Internal)
@testable import DatadogFlags

final class ExposureEventTests: XCTestCase {
    private func event(serialID: Int?) -> ExposureEvent {
        ExposureEvent(
            timestamp: 1_731_939_805_123,
            allocation: .init(key: "allocation-123"),
            flag: .init(key: "some-flag"),
            variant: .init(key: "variation-123"),
            serialID: serialID,
            subject: .init(id: "subject-1", attributes: [:])
        )
    }

    func testEncodingSerialIDAsSnakeCase() throws {
        // When
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(event(serialID: 0))) as? [String: Any]

        // Then
        XCTAssertEqual(try XCTUnwrap(json)["serial_id"] as? Int, 0)
    }

    func testEncodingOmitsAbsentSerialID() throws {
        // When
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(event(serialID: nil))) as? [String: Any]

        // Then
        XCTAssertFalse(try XCTUnwrap(json).keys.contains("serial_id"))
    }
}
