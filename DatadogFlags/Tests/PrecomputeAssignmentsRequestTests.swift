/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogFlags

final class PrecomputeAssignmentsRequestTests: XCTestCase {
    func testRequestModelEncoding() throws {
        // Given
        let request = PrecomputeAssignmentsRequest(
            data: PrecomputeAssignmentsRequest.DataContainer(
                type: "precompute-assignments-request",
                attributes: PrecomputeAssignmentsRequest.Attributes(
                    environment: PrecomputeAssignmentsRequest.Attributes.Environment(
                        name: "production",
                        ddEnv: "production"
                    ),
                    subject: PrecomputeAssignmentsRequest.Attributes.Subject(
                        targetingKey: "user123",
                        targetingAttributes: [
                            "userId": "123",
                            "plan": "premium"
                        ]
                    )
                )
            )
        )

        // When
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Then
        XCTAssertNotNil(json)

        let dataContainer = json?["data"] as? [String: Any]
        XCTAssertEqual(dataContainer?["type"] as? String, "precompute-assignments-request")

        let attributes = dataContainer?["attributes"] as? [String: Any]
        XCTAssertNotNil(attributes)

        let environment = attributes?["environment"] as? [String: Any]
        XCTAssertEqual(environment?["name"] as? String, "production")
        XCTAssertEqual(environment?["dd_env"] as? String, "production")

        let subject = attributes?["subject"] as? [String: Any]
        XCTAssertEqual(subject?["targeting_key"] as? String, "user123")

        let targetingAttributes = subject?["targeting_attributes"] as? [String: String]
        XCTAssertEqual(targetingAttributes?["userId"], "123")
        XCTAssertEqual(targetingAttributes?["plan"], "premium")
    }

    func testCodingKeysMapping() throws {
        // Test that CodingKeys correctly map snake_case to camelCase
        let request = PrecomputeAssignmentsRequest(
            data: PrecomputeAssignmentsRequest.DataContainer(
                type: "test",
                attributes: PrecomputeAssignmentsRequest.Attributes(
                    environment: PrecomputeAssignmentsRequest.Attributes.Environment(
                        name: "test",
                        ddEnv: "test"
                    ),
                    subject: PrecomputeAssignmentsRequest.Attributes.Subject(
                        targetingKey: "key",
                        targetingAttributes: [:]
                    )
                )
            )
        )

        let data = try JSONEncoder().encode(request)
        let jsonString = String(data: data, encoding: .utf8)!

        // Verify snake_case keys are present in JSON
        XCTAssertTrue(jsonString.contains("\"dd_env\""))
        XCTAssertTrue(jsonString.contains("\"targeting_key\""))
        XCTAssertTrue(jsonString.contains("\"targeting_attributes\""))

        // Verify camelCase keys are NOT present
        XCTAssertFalse(jsonString.contains("\"ddEnv\""))
        XCTAssertFalse(jsonString.contains("\"targetingKey\""))
        XCTAssertFalse(jsonString.contains("\"targetingAttributes\""))
    }
}
