/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogFlags

final class FlagAssignmentsResponseTests: XCTestCase {
    func testDecoding() throws {
        // Given
        let json = """
        {
          "data": {
            "id": "test_subject",
            "type": "precomputed-assignments",
            "attributes": {
              "createdAt": 1731939805123,
              "environment": {
                "name": "prod"
              },
              "flags": {
                "string-flag": {
                  "allocationKey": "allocation-123",
                  "variationKey": "variation-123",
                  "variationType": "string",
                  "variationValue": "red",
                  "extraLogging": {
                    "experiment": true
                  },
                  "doLog": true,
                  "reason": "TARGETING_MATCH"
                },
                "boolean-flag": {
                  "allocationKey": "allocation-124",
                  "variationKey": "variation-124",
                  "variationType": "boolean",
                  "variationValue": true,
                  "extraLogging": {
                    "experiment": true
                  },
                  "doLog": true,
                  "reason": "TARGETING_MATCH"
                },
                "integer-flag": {
                  "allocationKey": "allocation-125",
                  "variationKey": "variation-125",
                  "variationType": "integer",
                  "variationValue": 42,
                  "extraLogging": {
                    "experiment": true
                  },
                  "doLog": true,
                  "reason": "TARGETING_MATCH"
                },
                "numeric-flag": {
                  "allocationKey": "allocation-126",
                  "variationKey": "variation-126",
                  "variationType": "float",
                  "variationValue": 3.14,
                  "extraLogging": {
                    "experiment": true
                  },
                  "doLog": true,
                  "reason": "TARGETING_MATCH"
                },
                "legacy-number-flag": {
                  "allocationKey": "allocation-128",
                  "variationKey": "variation-128",
                  "variationType": "number",
                  "variationValue": 99,
                  "extraLogging": {
                    "experiment": true
                  },
                  "doLog": true,
                  "reason": "TARGETING_MATCH"
                },
                "json-flag": {
                  "allocationKey": "allocation-127",
                  "variationKey": "variation-127",
                  "variationType": "object",
                  "variationValue": { "key": "value", "prop": 123 },
                  "extraLogging": {
                    "experiment": true
                  },
                  "doLog": true,
                  "reason": "TARGETING_MATCH"
                }
              }
            }
          }
        }
        """.data(using: .utf8)!

        // When
        let response = try JSONDecoder().decode(FlagAssignmentsResponse.self, from: json)

        // Then
        XCTAssertEqual(
            response,
            FlagAssignmentsResponse(
                flags: [
                    "string-flag": .init(
                        allocationKey: "allocation-123",
                        variationKey: "variation-123",
                        variation: .string("red"),
                        reason: "TARGETING_MATCH",
                        doLog: true
                    ),
                    "boolean-flag": .init(
                        allocationKey: "allocation-124",
                        variationKey: "variation-124",
                        variation: .boolean(true),
                        reason: "TARGETING_MATCH",
                        doLog: true
                    ),
                    "integer-flag": .init(
                        allocationKey: "allocation-125",
                        variationKey: "variation-125",
                        variation: .integer(42),
                        reason: "TARGETING_MATCH",
                        doLog: true
                    ),
                    "numeric-flag": .init(
                        allocationKey: "allocation-126",
                        variationKey: "variation-126",
                        variation: .double(3.14),
                        reason: "TARGETING_MATCH",
                        doLog: true
                    ),
                    "legacy-number-flag": .init(
                        allocationKey: "allocation-128",
                        variationKey: "variation-128",
                        variation: .integer(99),
                        reason: "TARGETING_MATCH",
                        doLog: true
                    ),
                    "json-flag": .init(
                        allocationKey: "allocation-127",
                        variationKey: "variation-127",
                        variation: .object(.dictionary([
                            "key": .string("value"),
                            "prop": .int(123),
                        ])),
                        reason: "TARGETING_MATCH",
                        doLog: true
                    ),
                ]
            )
        )
    }

    func testDecodingWithBrokenFlags_healsFromInvalidVariationType() throws {
        // Given
        let json = """
        {
          "data": {
            "id": "test_subject",
            "type": "precomputed-assignments",
            "attributes": {
              "createdAt": 1731939805123,
              "environment": {
                "name": "prod"
              },
              "flags": {
                "valid-string-flag": {
                  "allocationKey": "allocation-123",
                  "variationKey": "variation-123",
                  "variationType": "string",
                  "variationValue": "red",
                  "doLog": true,
                  "reason": "TARGETING_MATCH"
                },
                "broken-flag": {
                  "allocationKey": "allocation-999",
                  "variationKey": "variation-999",
                  "variationType": "NEW_VARIANT_TYPE",
                  "variationValue": "something",
                  "doLog": true,
                  "reason": "TARGETING_MATCH"
                },
                "valid-boolean-flag": {
                  "allocationKey": "allocation-124",
                  "variationKey": "variation-124",
                  "variationType": "boolean",
                  "variationValue": true,
                  "doLog": true,
                  "reason": "TARGETING_MATCH"
                },
                "another-broken-flag": {
                  "allocationKey": "allocation-998",
                  "variationKey": "variation-998",
                  "variationType": "ANOTHER_NEW_TYPE",
                  "variationValue": 123,
                  "doLog": true,
                  "reason": "TARGETING_MATCH"
                },
                "valid-integer-flag": {
                  "allocationKey": "allocation-125",
                  "variationKey": "variation-125",
                  "variationType": "integer",
                  "variationValue": 42,
                  "doLog": true,
                  "reason": "TARGETING_MATCH"
                }
              }
            }
          }
        }
        """.data(using: .utf8)!

        // When
        let response = try JSONDecoder().decode(FlagAssignmentsResponse.self, from: json)

        // Then - Verify valid flags were decoded successfully
        XCTAssertEqual(response.flags.count, 3, "Should have 3 valid flags")
        XCTAssertEqual(
            response.flags["valid-string-flag"],
            .init(
                allocationKey: "allocation-123",
                variationKey: "variation-123",
                variation: .string("red"),
                reason: "TARGETING_MATCH",
                doLog: true
            )
        )
        XCTAssertEqual(
            response.flags["valid-boolean-flag"],
            .init(
                allocationKey: "allocation-124",
                variationKey: "variation-124",
                variation: .boolean(true),
                reason: "TARGETING_MATCH",
                doLog: true
            )
        )
        XCTAssertEqual(
            response.flags["valid-integer-flag"],
            .init(
                allocationKey: "allocation-125",
                variationKey: "variation-125",
                variation: .integer(42),
                reason: "TARGETING_MATCH",
                doLog: true
            )
        )

        // Then - Verify broken flags were captured
        XCTAssertEqual(response.failedFlags.count, 2, "Should have 2 failed flags")
        XCTAssertTrue(response.failedFlags.keys.contains("broken-flag"), "Should contain broken-flag")
        XCTAssertTrue(response.failedFlags.keys.contains("another-broken-flag"), "Should contain another-broken-flag")

        // Verify the error messages contain information about the unknown type
        let brokenFlagError = try XCTUnwrap(response.failedFlags["broken-flag"])
        XCTAssertTrue(brokenFlagError.contains("NEW_VARIANT_TYPE"), "Error should mention the unknown variant type")

        let anotherBrokenFlagError = try XCTUnwrap(response.failedFlags["another-broken-flag"])
        XCTAssertTrue(anotherBrokenFlagError.contains("ANOTHER_NEW_TYPE"), "Error should mention the unknown variant type")
    }
}
