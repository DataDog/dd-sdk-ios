/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@_spi(Internal)
@testable import DatadogFlags

final class FlagAssignmentsResponseTests: XCTestCase {
    func testCachedAssignmentEqualityAndSerialization() throws {
        let cached = FlagAssignment(
            allocationKey: "allocation",
            variationKey: "variant",
            variation: .boolean(true),
            reason: "CACHED",
            doLog: true,
            serialID: 42
        )
        let changes: [(inout FlagAssignment) -> Void] = [
            { $0.allocationKey = "other" },
            { $0.variationKey = "other" },
            { $0.variation = .boolean(false) },
            { $0.reason = "other" },
            { $0.doLog = false },
            { $0.serialID = 43 },
            { $0.isNumberType = true }
        ]
        for change in changes {
            var changed = cached
            change(&changed)
            XCTAssertNotEqual(cached, changed)
        }
        let encoded = try JSONEncoder().encode(cached)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(object.keys), [
            "allocationKey", "variationKey", "variationType", "variationValue", "reason", "doLog", "serialId"
        ])
        XCTAssertEqual(object["reason"] as? String, "CACHED")
        let decoded = try JSONDecoder().decode(FlagAssignment.self, from: encoded)
        XCTAssertEqual(decoded, cached)
    }

    func testCacheProjectionChangesEqualityThroughExposedReason() {
        let networkDefault = FlagAssignment(
            allocationKey: "allocation",
            variationKey: "variant",
            variation: .boolean(true),
            reason: "DEFAULT",
            doLog: true
        )
        var networkMatch = networkDefault
        networkMatch.reason = "TARGETING_MATCH"
        XCTAssertNotEqual(networkDefault, networkMatch)

        var cachedDefault = networkDefault
        cachedDefault.reason = "CACHED"
        var cachedMatch = networkMatch
        cachedMatch.reason = "CACHED"

        XCTAssertNotEqual(cachedDefault, networkDefault)
        XCTAssertNotEqual(cachedMatch, networkMatch)
        XCTAssertEqual(cachedDefault, cachedMatch)
    }

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
                    "legacy-number-flag": FlagAssignment(
                        allocationKey: "allocation-128",
                        variationKey: "variation-128",
                        variation: .integer(99),
                        reason: "TARGETING_MATCH",
                        doLog: true
                    ).servedAsNumber(),
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

    func testDecodingFlagAssignmentsResponseWithUnknownVariationTypes() throws {
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

    func testDecodingSerialID() throws {
        // Given
        let withSerialIDEntry = { (entry: String) in
            """
            {
              "allocationKey": "allocation-123",
              "variationKey": "variation-123",
              "variationType": "string",
              "variationValue": "red",
              "doLog": true,
              "reason": "TARGETING_MATCH"\(entry)
            }
            """.data(using: .utf8)!
        }

        // When
        let withZero = try JSONDecoder().decode(FlagAssignment.self, from: withSerialIDEntry(#", "serialId": 0"#))
        let withValue = try JSONDecoder().decode(FlagAssignment.self, from: withSerialIDEntry(#", "serialId": 340132"#))
        let withNull = try JSONDecoder().decode(FlagAssignment.self, from: withSerialIDEntry(#", "serialId": null"#))
        let withoutKey = try JSONDecoder().decode(FlagAssignment.self, from: withSerialIDEntry(""))
        let withString = try JSONDecoder().decode(FlagAssignment.self, from: withSerialIDEntry(#", "serialId": "abc""#))
        let withFraction = try JSONDecoder().decode(FlagAssignment.self, from: withSerialIDEntry(#", "serialId": 3.7"#))

        // Then
        XCTAssertEqual(withZero.serialID, 0)
        XCTAssertEqual(withValue.serialID, 340_132)
        XCTAssertNil(withNull.serialID, "An explicit null must decode as an absent serial id")
        XCTAssertNil(withoutKey.serialID)
        XCTAssertNil(withString.serialID, "A malformed serial id must decode as absent")
        XCTAssertNil(withFraction.serialID, "A malformed serial id must decode as absent")
        XCTAssertEqual(withString.variation, .string("red"), "The rest of the flag must still decode")
    }

    func testDecodingMalformedSerialIDDoesNotFailSiblingFlags() throws {
        // Given
        let json = """
        {
          "data": {
            "id": "test_subject",
            "type": "precomputed-assignments",
            "attributes": {
              "flags": {
                "broken-serial-id-flag": {
                  "allocationKey": "allocation-123",
                  "variationKey": "variation-123",
                  "variationType": "string",
                  "variationValue": "red",
                  "doLog": true,
                  "reason": "TARGETING_MATCH",
                  "serialId": "not-an-integer"
                },
                "healthy-flag": {
                  "allocationKey": "allocation-124",
                  "variationKey": "variation-124",
                  "variationType": "boolean",
                  "variationValue": true,
                  "doLog": true,
                  "reason": "TARGETING_MATCH",
                  "serialId": 0
                }
              }
            }
          }
        }
        """.data(using: .utf8)!

        // When
        let response = try JSONDecoder().decode(FlagAssignmentsResponse.self, from: json)

        // Then
        XCTAssertEqual(response.flags.count, 2)
        XCTAssertNil(try XCTUnwrap(response.flags["broken-serial-id-flag"]).serialID)
        XCTAssertEqual(try XCTUnwrap(response.flags["healthy-flag"]).serialID, 0)
        XCTAssertEqual(response.failedFlags, [:])
    }

    func testEncodingSerialID() throws {
        // Given
        let assignment = FlagAssignment(
            allocationKey: "allocation-123",
            variationKey: "variation-123",
            variation: .string("red"),
            reason: "TARGETING_MATCH",
            doLog: true,
            serialID: 0
        )
        var withoutSerialID = assignment
        withoutSerialID.serialID = nil

        // When
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(assignment)) as? [String: Any]
        let encodedWithoutSerialID = try JSONSerialization.jsonObject(with: JSONEncoder().encode(withoutSerialID)) as? [String: Any]

        // Then
        XCTAssertEqual(try XCTUnwrap(encoded)["serialId"] as? Int, 0)
        XCTAssertFalse(try XCTUnwrap(encodedWithoutSerialID).keys.contains("serialId"))
    }

    func testDecodingFlagAssignmentWithUnknownVariationType() throws {
        // Given
        let json = """
        {
          "allocationKey": "allocation-999",
          "variationKey": "variation-999",
          "variationType": "FUTURE_TYPE",
          "variationValue": "something",
          "doLog": true,
          "reason": "TARGETING_MATCH"
        }
        """.data(using: .utf8)!

        // When
        let assignment = try JSONDecoder().decode(FlagAssignment.self, from: json)

        // Then - Verify it decoded successfully with unknown variation
        XCTAssertEqual(assignment.allocationKey, "allocation-999")
        XCTAssertEqual(assignment.variationKey, "variation-999")
        XCTAssertEqual(assignment.reason, "TARGETING_MATCH")
        XCTAssertTrue(assignment.doLog)

        // Verify the variation is .unknown with the correct type name
        if case .unknown(let typeName) = assignment.variation {
            XCTAssertEqual(typeName, "FUTURE_TYPE")
        } else {
            XCTFail("Expected .unknown variation, got \(assignment.variation)")
        }

        // Verify variation(as:) returns nil for unknown types
        XCTAssertNil(assignment.variation(as: String.self))
        XCTAssertNil(assignment.variation(as: Bool.self))
        XCTAssertNil(assignment.variation(as: Int.self))
        XCTAssertNil(assignment.variation(as: Double.self))
    }

    func testWholeNumberVariationsCanBeReadAsDouble() throws {
        func assignment(type: String, value: String) throws -> FlagAssignment {
            let json = """
            {
              "allocationKey": "allocation",
              "variationKey": "variation",
              "variationType": "\(type)",
              "variationValue": \(value),
              "doLog": false,
              "reason": "TARGETING_MATCH"
            }
            """.data(using: .utf8)!
            return try JSONDecoder().decode(FlagAssignment.self, from: json)
        }

        // Given - "number" assignments with a whole and a fractional value
        let wholeNumber = try assignment(type: "number", value: "5")
        let fractionalNumber = try assignment(type: "number", value: "5.5")
        let integer = try assignment(type: "integer", value: "7")

        // Then - a whole number reads as both Int and Double
        XCTAssertEqual(wholeNumber.variation(as: Int.self), 5)
        XCTAssertEqual(wholeNumber.variation(as: Double.self), 5.0)
        XCTAssertEqual(fractionalNumber.variation(as: Double.self), 5.5)
        XCTAssertNil(fractionalNumber.variation(as: Int.self))
        XCTAssertEqual(try assignment(type: "number", value: "0").variation(as: Double.self), 0.0)
        XCTAssertEqual(try assignment(type: "number", value: "0").variation(as: Int.self), 0)
        XCTAssertEqual(try assignment(type: "number", value: "-5").variation(as: Double.self), -5.0)
        XCTAssertEqual(try assignment(type: "number", value: "-5").variation(as: Int.self), -5)

        // Numeric labels do not restrict exact conversions.
        XCTAssertEqual(integer.variation(as: Int.self), 7)
        XCTAssertEqual(integer.variation(as: Double.self), 7.0)

        // A whole value served as "float" also reads as Int.
        let wholeFloat = try assignment(type: "float", value: "5")
        XCTAssertEqual(wholeFloat.variation(as: Double.self), 5.0)
        XCTAssertEqual(wholeFloat.variation(as: Int.self), 5)

        // A cached assignment keeps its type, so these reads do not change after a restart
        let cachedNumber = try JSONDecoder().decode(FlagAssignment.self, from: JSONEncoder().encode(wholeNumber))
        XCTAssertEqual(cachedNumber, wholeNumber)
        XCTAssertEqual(cachedNumber.variation(as: Double.self), 5.0)
        XCTAssertEqual(cachedNumber.variation(as: Int.self), 5)
        let cachedInteger = try JSONDecoder().decode(FlagAssignment.self, from: JSONEncoder().encode(integer))
        XCTAssertEqual(cachedInteger, integer)
        XCTAssertEqual(cachedInteger.variation(as: Double.self), 7.0)
        XCTAssertEqual(try JSONDecoder().decode(FlagAssignment.self, from: JSONEncoder().encode(fractionalNumber)), fractionalNumber)
        let cachedFloat = try JSONDecoder().decode(FlagAssignment.self, from: JSONEncoder().encode(wholeFloat))
        XCTAssertEqual(cachedFloat, wholeFloat)
        XCTAssertEqual(cachedFloat.variation(as: Double.self), 5.0)
        XCTAssertEqual(cachedFloat.variation(as: Int.self), 5)

        // A "number" that decodes as `.double` is not marked, so the cache writes it as "float".
        // A whole Double must stay `.double`: some JSON decoders produce one for values such as 999999999999999.99.
        XCTAssertFalse(fractionalNumber.isNumberType)
        var wholeDouble = fractionalNumber
        wholeDouble.variation = .double(1e15)
        let cachedWholeDouble = try JSONDecoder().decode(FlagAssignment.self, from: JSONEncoder().encode(wholeDouble))
        XCTAssertEqual(cachedWholeDouble.variation(as: Double.self), wholeDouble.variation(as: Double.self))
        XCTAssertEqual(cachedWholeDouble.variation(as: Int.self), 1_000_000_000_000_000)
        let rounded = try assignment(type: "number", value: "999999999999999.99")
        XCTAssertEqual(try JSONDecoder().decode(FlagAssignment.self, from: JSONEncoder().encode(rounded)), rounded)

        // Other types still do not convert
        XCTAssertNil(wholeNumber.variation(as: String.self))
        XCTAssertNil(wholeNumber.variation(as: Bool.self))
    }
}
