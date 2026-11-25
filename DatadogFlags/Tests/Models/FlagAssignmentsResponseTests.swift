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
    func testOriginalNumericTokensSurviveGettersAndCache() throws {
        let cases: [(String, Int?, Double?)] = [
            ("5.0", 5, 5), ("1.20000000000000001", nil, 1.2),
            ("1.00000000000000001", nil, 1),
            ("4503599627370497.5", nil, 4_503_599_627_370_498),
            ("9007199254740993.5", nil, 9_007_199_254_740_994),
            ("9007199254740993", Int("9007199254740993"), nil),
            ("1e-400", nil, nil), ("1e400", nil, nil),
            ("0e999999", 0, 0), ("-0.0", 0, 0)
        ]
        for label in ["number", "integer", "float"] {
            for (literal, integer, double) in cases {
                let json = #"{"allocationKey":"a","variationKey":"v","variationType":"\#(label)","variationValue":\#(literal),"reason":"STATIC","doLog":false}"#
                let assignment = try FlagsNumericJSON.decode(FlagAssignment.self, from: Data(json.utf8))
                let restored = try FlagsNumericJSON.decode(FlagAssignment.self, from: JSONEncoder().encode(assignment), cached: true)
                for value in [assignment, restored] {
                    XCTAssertEqual(value.variation(as: Int.self), integer, "\(label): \(literal)")
                    XCTAssertEqual(value.variation(as: Double.self), double, "\(label): \(literal)")
                }
            }
        }
    }

    func testNumericMetadataCannotOverrideTheWireValue() throws {
        let json = #"{"allocationKey":"a","variationKey":"v","variationType":"number","variationValue":5,"_numericLiteral":"1e400","reason":"STATIC","doLog":false}"#
        let assignment = try FlagsNumericJSON.decode(FlagAssignment.self, from: Data(json.utf8))
        XCTAssertEqual(assignment.variation(as: Int.self), 5)
        let stringValue = json.replacingOccurrences(of: #""variationValue":5"#, with: #""variationValue":"5""#)
        XCTAssertThrowsError(try FlagsNumericJSON.decode(FlagAssignment.self, from: Data(stringValue.utf8)))
    }
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
            { $0.observeFullEvaluationData = true }
        ]
        for change in changes {
            var changed = cached
            change(&changed)
            XCTAssertNotEqual(cached, changed)
        }
        let encoded = try JSONEncoder().encode(cached)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(object.keys), [
            "allocationKey", "variationKey", "variationType", "variationValue", "reason", "doLog", "serialId", "observeFullEvaluationData"
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

    func testNumericVariationsConvertWithoutLoss() throws {
        func decoded(type: String, value: String) throws -> FlagAssignment {
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
            return try FlagsNumericJSON.decode(FlagAssignment.self, from: json)
        }
        func built(_ variation: FlagAssignment.Variation) -> FlagAssignment {
            FlagAssignment(
                allocationKey: "allocation",
                variationKey: "variation",
                variation: variation,
                reason: "TARGETING_MATCH",
                doLog: false
            )
        }
        // Encodes and decodes like the flags cache
        func cached(_ assignment: FlagAssignment) throws -> FlagAssignment {
            try FlagsNumericJSON.decode(FlagAssignment.self, from: JSONEncoder().encode(assignment), cached: true)
        }

        // A whole value reads as Int and Double, whatever its served numeric type, also after a cache restore
        for type in ["number", "integer", "float"] {
            let whole = try decoded(type: type, value: "5")
            XCTAssertEqual(whole.variation(as: Int.self), 5, type)
            XCTAssertEqual(whole.variation(as: Double.self), 5.0, type)
            XCTAssertEqual(try cached(whole), whole, type)
            XCTAssertEqual(try cached(whole).variation(as: Int.self), 5, type)
            XCTAssertEqual(try cached(whole).variation(as: Double.self), 5.0, type)
        }
        XCTAssertEqual(try decoded(type: "number", value: "0").variation(as: Double.self), 0.0)
        XCTAssertEqual(try decoded(type: "number", value: "-5").variation(as: Double.self), -5.0)
        XCTAssertEqual(try decoded(type: "number", value: "-5").variation(as: Int.self), -5)

        // Whole decimal and exponent spellings read as Int
        for type in ["number", "integer", "float"] {
            for (literal, expected) in [("5.0", 5), ("1e3", 1_000), ("-0.0", 0)] {
                let whole = try decoded(type: type, value: literal)
                XCTAssertEqual(whole.variation(as: Int.self), expected, "\(type) \(literal)")
                XCTAssertEqual(whole.variation(as: Double.self), Double(expected), "\(type) \(literal)")
                XCTAssertEqual(try cached(whole).variation(as: Int.self), expected, "\(type) \(literal)")
            }
        }

        // SDK 3.21.0 and earlier write `.integer` variations to the cache as "integer"
        XCTAssertEqual(try decoded(type: "integer", value: "7").variation(as: Double.self), 7.0)
        let number = try decoded(type: "number", value: "5")
        XCTAssertEqual(number, try decoded(type: "integer", value: "5"))
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(number)) as? [String: Any])
        XCTAssertEqual(encoded["variationType"] as? String, "integer")

        // A fractional value reads only as Double, whatever its served numeric type
        for type in ["number", "integer", "float"] {
            let fractional = try decoded(type: type, value: "5.5")
            XCTAssertEqual(fractional.variation(as: Double.self), 5.5, type)
            XCTAssertNil(fractional.variation(as: Int.self), type)
            XCTAssertEqual(try cached(fractional), fractional, type)
            XCTAssertNil(try cached(fractional).variation(as: Int.self), type)
        }

        // The `_pointerBitWidth(_64)` blocks need a 64-bit Int, because their values or results depend on
        // the width of Int.

        // Values without original numeric tokens keep the conservative Double-to-Int limit.
        #if _pointerBitWidth(_64)
        XCTAssertEqual(built(.double(9_007_199_254_740_991)).variation(as: Int.self), 9_007_199_254_740_991)
        XCTAssertEqual(built(.double(-9_007_199_254_740_991)).variation(as: Int.self), -9_007_199_254_740_991)
        #endif
        XCTAssertNil(built(.double(9_007_199_254_740_992)).variation(as: Int.self))
        XCTAssertNil(built(.double(-9_007_199_254_740_992)).variation(as: Int.self))
        XCTAssertNil(built(.double(1e20)).variation(as: Int.self))
        XCTAssertNil(built(.double(.infinity)).variation(as: Int.self))
        XCTAssertNil(built(.double(.nan)).variation(as: Int.self))
        XCTAssertNil(built(.double(.infinity)).variation(as: Double.self))
        XCTAssertNil(built(.double(.nan)).variation(as: Double.self))

        // An Int converts to Double only when the Double represents it exactly
        #if _pointerBitWidth(_64)
        XCTAssertEqual(built(.integer(1 << 60)).variation(as: Double.self), 1_152_921_504_606_846_976.0)
        XCTAssertNil(built(.integer((1 << 53) + 1)).variation(as: Double.self))
        XCTAssertNil(built(.integer(Int.max)).variation(as: Double.self))
        #endif

        // A stored `.double` keeps its representation through the cache, so its reads do not change
        let wholeDouble = built(.double(1e15))
        XCTAssertEqual(try cached(wholeDouble), wholeDouble)
        #if _pointerBitWidth(_64)
        XCTAssertEqual(wholeDouble.variation(as: Int.self), 1_000_000_000_000_000)
        XCTAssertEqual(try cached(wholeDouble).variation(as: Int.self), 1_000_000_000_000_000)
        #endif
        for value in [9_007_199_254_740_994.0, 1_000_000_000_000_000_128.0, -9_007_199_254_740_994.0, 5.5] {
            let stored = built(.double(value))
            XCTAssertEqual(try cached(stored), stored, "\(value)")
            XCTAssertNil(try cached(stored).variation(as: Int.self), "\(value)")
            XCTAssertEqual(try cached(stored).variation(as: Double.self), value, "\(value)")
        }
        // Outside the cache, a whole value written as a number decodes as `.integer`
        #if _pointerBitWidth(_64)
        XCTAssertEqual(
            try JSONDecoder().decode(FlagAssignment.self, from: JSONEncoder().encode(wholeDouble)).variation,
            .integer(1_000_000_000_000_000)
        )
        #endif
        let rounded = try decoded(type: "number", value: "999999999999999.99")
        XCTAssertEqual(try cached(rounded), rounded)

        // A whole value above 2^53 keeps every digit, whatever its served numeric type
        #if _pointerBitWidth(_64)
        for type in ["number", "integer", "float"] {
            let large = try decoded(type: type, value: "9007199254740993")
            XCTAssertEqual(large.variation(as: Int.self), 9_007_199_254_740_993, type)
            XCTAssertNil(large.variation(as: Double.self), type)
            XCTAssertEqual(try cached(large).variation(as: Int.self), 9_007_199_254_740_993, type)
        }
        #endif
        XCTAssertEqual(try decoded(type: "float", value: "\(Int.max)").variation(as: Int.self), .max)
        XCTAssertEqual(try decoded(type: "integer", value: "\(Int.max)").variation(as: Int.self), .max)
        XCTAssertEqual(try decoded(type: "number", value: "\(Int.min)").variation(as: Double.self), Double(Int.min))
        let huge = try decoded(type: "number", value: "1e20")
        XCTAssertEqual(huge.variation(as: Double.self), 1e20)
        XCTAssertNil(huge.variation(as: Int.self))

        // Other types still do not convert
        let whole = try decoded(type: "number", value: "5")
        XCTAssertNil(whole.variation(as: String.self))
        XCTAssertNil(whole.variation(as: Bool.self))
    }
}

extension FlagAssignmentsResponseTests {
    func testConsentIsTolerantAndPersistedWithTheWholeConfiguration() throws {
        let fields = [
            "", ", \"observeFullEvaluationData\": true", ", \"observeFullEvaluationData\": false",
            ", \"observeFullEvaluationData\": null", ", \"observeFullEvaluationData\": \"true\"",
            ", \"observeFullEvaluationData\": 1", ", \"observeFullEvaluationData\": {}"
        ]
        for field in fields {
            let json = """
            {"data":{"attributes":{"flags":{"flag":{"allocationKey":"a","variationKey":"v",
            "variationType":"boolean","variationValue":true,"reason":"MATCH","doLog":false,
            "observeFullEvaluationData":true}}\(field)}}}
            """
            let response = try JSONDecoder().decode(FlagAssignmentsResponse.self, from: Data(json.utf8))
            let expected = field == ", \"observeFullEvaluationData\": true"
            XCTAssertEqual(response.observeFullEvaluationData, expected)
            XCTAssertEqual(response.flags["flag"]?.observeFullEvaluationData, expected)
            let data = FlagsData(flags: response.flags, context: .mockAny(), date: .mockAny(), observeFullEvaluationData: expected)
            let encoded = try JSONEncoder().encode(data)
            XCTAssertEqual(try JSONDecoder().decode(FlagsData.self, from: encoded), data)
            var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            legacy.removeValue(forKey: "observeFullEvaluationData")
            let restored = try JSONDecoder().decode(FlagsData.self, from: JSONSerialization.data(withJSONObject: legacy))
            XCTAssertFalse(restored.observeFullEvaluationData)
            XCTAssertEqual(restored.flags["flag"]?.observeFullEvaluationData, false)
        }
    }
}

extension FlagAssignmentsResponseTests {
    /// Older `JSONDecoder` implementations report `["flags", key]` inside a flag assignment, because they do not
    /// keep the `data` and `attributes` container keys. This decoder reports that same short path.
    private struct ShortCodingPathDecoder: Decoder {
        let base: Decoder
        let codingPath: [CodingKey]
        var userInfo: [CodingUserInfoKey: Any] { base.userInfo }
        func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> { try base.container(keyedBy: type) }
        func unkeyedContainer() throws -> UnkeyedDecodingContainer { try base.unkeyedContainer() }
        func singleValueContainer() throws -> SingleValueDecodingContainer { try base.singleValueContainer() }
    }

    private struct ShortCodingPathResponse: FlagNumericTokenRoot {
        static var flagAssignmentsPath: [String] { ["data", "attributes", "flags"] }

        struct Key: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        var flags: [String: FlagAssignment] = [:]

        init(from decoder: Decoder) throws {
            let flagsContainer = try decoder.container(keyedBy: Key.self)
                .nestedContainer(keyedBy: Key.self, forKey: Key(stringValue: "data"))
                .nestedContainer(keyedBy: Key.self, forKey: Key(stringValue: "attributes"))
                .nestedContainer(keyedBy: Key.self, forKey: Key(stringValue: "flags"))
            for key in flagsContainer.allKeys {
                let shortPath = ShortCodingPathDecoder(
                    base: try flagsContainer.superDecoder(forKey: key),
                    codingPath: [Key(stringValue: "flags"), key]
                )
                flags[key.stringValue] = try FlagAssignment(from: shortPath)
            }
        }
    }

    func testNumericTokensResolveByFlagKeyWhenTheDecoderDropsNestedContainerKeys() throws {
        let cases: [(String, Int?, Double?)] = [
            ("4503599627370497.5", nil, 4_503_599_627_370_498),
            ("1.00000000000000001", nil, 1),
            ("5.0", 5, 5)
        ]
        for (literal, integer, double) in cases {
            let json = """
            {"data":{"attributes":{"flags":{"my-flag":{"allocationKey":"a","variationKey":"v","variationType":"number",
            "variationValue":\(literal),"reason":"STATIC","doLog":false}}}}}
            """
            let response = try FlagsNumericJSON.decode(ShortCodingPathResponse.self, from: Data(json.utf8))
            let assignment = try XCTUnwrap(response.flags["my-flag"], literal)
            XCTAssertEqual(assignment.variation(as: Int.self), integer, literal)
            XCTAssertEqual(assignment.variation(as: Double.self), double, literal)
        }
    }

    func testMalformedNumberTokensRejectTheResponse() {
        for literal in ["1e+", "1e", "1.", "1.e5", "-", "01", "-01", "1-2", "1e+-2", "0x10"] {
            let json = #"{"data":{"attributes":{"flags":{"flag":{"allocationKey":"a","variationKey":"v","variationType":"number","variationValue":\#(literal),"reason":"STATIC","doLog":false}}}}}"#
            XCTAssertThrowsError(try FlagsNumericJSON.decode(FlagAssignmentsResponse.self, from: Data(json.utf8)), literal)
        }
        for literal in ["0", "-0", "1e400", "1e-400", "1.5E+2", "100000000000000000001"] {
            let json = #"{"data":{"attributes":{"flags":{"flag":{"allocationKey":"a","variationKey":"v","variationType":"number","variationValue":\#(literal),"reason":"STATIC","doLog":false}}}}}"#
            XCTAssertNoThrow(try FlagsNumericJSON.decode(FlagAssignmentsResponse.self, from: Data(json.utf8)), literal)
        }
    }
}

final class FlagKeySpellingsTests: XCTestCase {
    private let composed = "caf\u{00E9}"
    private let decomposed = "cafe\u{0301}"

    /// Breaks if `mayContainNonASCIIKeys` stops treating `\u` escapes as possible non-ASCII keys.
    func testKeySpellingsAreFoundInPrettyPrintedASCIIOnlyResponses() throws {
        let body = """
        {
          "data": {
            "attributes": {
              "flags": {
                "caf\\u00e9": {"allocationKey": "a", "variationKey": "composed", "variationType": "string", "variationValue": "composed", "reason": "STATIC", "doLog": true},
                \t"cafe\\u0301" : {"allocationKey": "a", "variationKey": "decomposed", "variationType": "string", "variationValue": "decomposed", "reason": "STATIC", "doLog": true}
              }
            }
          }
        }
        """
        let data = Data(body.utf8)
        XCTAssertTrue(data.allSatisfy { $0 < 0x80 })
        let response = try FlagsNumericJSON.decode(FlagAssignmentsResponse.self, from: data).addingKeySpellings(from: data)
        let served = response.flags.map { ($0.key, $0.value.variationKey) } + response.keySpellings.map { ($0.key, $0.assignment.variationKey) }
        XCTAssertEqual(served.count, 2)
        XCTAssertEqual(served.first { $0.0.utf8.elementsEqual(composed.utf8) }?.1, "composed")
        XCTAssertEqual(served.first { $0.0.utf8.elementsEqual(decomposed.utf8) }?.1, "decomposed")
    }

    /// Breaks if the merged value that decoding kept is not removed before the members are rebuilt.
    func testKeySpellingsDropTheMergedValueWhenAMemberCannotBeRebuilt() throws {
        let valid = #"{"allocationKey":"a","variationKey":"valid","variationType":"string","variationValue":"valid","reason":"STATIC","doLog":true}"#
        let unknown = #"{"allocationKey":"a","variationKey":"unknown","variationType":"future-type","variationValue":1,"reason":"STATIC","doLog":true}"#
        let malformed = #"{"allocationKey":"a","variationKey":"malformed","variationType":"string","variationValue":"x","reason":"STATIC"}"#
        let validAssignment = try FlagsNumericJSON.decode(FlagAssignment.self, from: Data(valid.utf8))
        for (composedValue, label) in [(unknown, "unknown"), (malformed, "malformed")] {
            let body = #"{"data":{"attributes":{"flags":{"caf\#u{00E9}":\#(composedValue),"cafe\#u{0301}":\#(valid)}}}}"#
            let response = FlagAssignmentsResponse(flags: [composed: validAssignment]).addingKeySpellings(from: Data(body.utf8))
            let served = response.flags.map { ($0.key, $0.value) } + response.keySpellings.map { ($0.key, $0.assignment) }
            XCTAssertEqual(served.count, 1, label)
            XCTAssertNil(served.first { $0.0.utf8.elementsEqual(composed.utf8) }, label)
            XCTAssertEqual(served.first { $0.0.utf8.elementsEqual(decomposed.utf8) }?.1, validAssignment, label)
            if label == "unknown" {
                XCTAssertEqual(response.failedFlags.count, 1)
                XCTAssertEqual(response.failedFlags.first.map { Array($0.key.utf8) }, Array(composed.utf8))
            } else {
                XCTAssertTrue(response.failedFlags.isEmpty)
            }
        }
    }

    /// Breaks if colliding members skip the numeric token rules, or if the cache version ignores `keySpellings`.
    func testKeySpellingsSelectTheCacheVersionAndKeepNumericTokens() throws {
        let assignment = { (value: String) in
            #"{"allocationKey":"a","variationKey":"v","variationType":"number","variationValue":\#(value),"reason":"STATIC","doLog":false}"#
        }
        let selection = CanonicalFlagSelection(tags: ["mobile"], keyPatterns: [])
        let cases: [(literal: String, selection: CanonicalFlagSelection?, version: DataStoreKeyVersion)] = [
            ("1.00000000000000001", nil, 4),
            ("1.00000000000000001", selection, 4),
            ("2.5", selection, 3),
            ("2.5", nil, dataStoreDefaultKeyVersion)
        ]
        for (literal, selection, version) in cases {
            let body = #"{"data":{"attributes":{"flags":{"caf\#u{00E9}":\#(assignment("1")),"cafe\#u{0301}":\#(assignment(literal))}}}}"#
            let data = Data(body.utf8)
            let response = try FlagsNumericJSON.decode(FlagAssignmentsResponse.self, from: data).addingKeySpellings(from: data)
            let spelling = try XCTUnwrap(response.keySpellings.first, literal)
            XCTAssertEqual(Array(spelling.key.utf8), Array(decomposed.utf8), literal)
            XCTAssertEqual(response.flags[composed]?.variation(as: Int.self), 1, literal)
            XCTAssertNil(spelling.assignment.variation(as: Int.self), literal)
            XCTAssertEqual(spelling.assignment.variation(as: Double.self), Double(literal), literal)
            let flagsData = FlagsData(flags: response.flags, context: .mockAny(), date: .mockAny(), flagSelection: selection, keySpellings: response.keySpellings)
            let scope = FeatureScopeMock()
            scope.flagsDataStore.setFlagsData(flagsData, forClientNamed: "spellings")
            let stored = try XCTUnwrap(scope.dataStoreMock.storage["spellings"])
            for other: DataStoreKeyVersion in [1, 2, 3, 4] where other != version {
                XCTAssertNil(stored.data(expectedVersion: other), "\(literal) at \(other)")
            }
            XCTAssertNotNil(stored.data(expectedVersion: version), literal)
        }
    }

    /// Breaks if a cold start from the cache loses a spelling, its `CACHED` reason, or its first-flags key.
    func testOfflineRestartServesBothCachedSpellings() throws {
        let assignment = { (variant: String) in
            #"{"allocationKey":"a","variationKey":"\#(variant)","variationType":"string","variationValue":"\#(variant)","reason":"STATIC","doLog":true}"#
        }
        let body = #"{"data":{"attributes":{"flags":{"caf\#u{00E9}":\#(assignment("composed")),"cafe\#u{0301}":\#(assignment("decomposed"))}}}}"#
        let scope = FeatureScopeMock(context: .mockWith(source: "ios"))
        let clientName = UUID().uuidString
        let context = FlagsEvaluationContext(targetingKey: "subject")

        let online = FlagsRepository(
            clientName: clientName,
            flagAssignmentsFetcher: FlagAssignmentsFetcher(
                customEndpoint: nil,
                customHeaders: nil,
                flagSelection: nil,
                featureScope: scope,
                fetch: { _, complete in complete(.success((Data(body.utf8), .mockAny()))) }
            ),
            dateProvider: DateProviderMock(),
            featureScope: scope,
            flagSelection: nil,
            initializationTimeout: nil
        )
        let loaded = expectation(description: "online configuration loaded")
        online.setEvaluationContext(context) { _ in loaded.fulfill() }
        wait(for: [loaded], timeout: 2)
        online.flush()

        let offline = FlagsRepository(
            clientName: clientName,
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, complete in
                complete(.failure(.networkError(URLError(.notConnectedToInternet))))
            },
            dateProvider: DateProviderMock(),
            featureScope: scope,
            flagSelection: nil,
            initializationTimeout: nil
        )
        let firstFlags = expectation(description: "first flags from cache")
        let keys = ReadWriteLock<[[UInt8]]>(wrappedValue: [])
        _ = offline.onFirstFlags { event in
            keys.wrappedValue = event.flagsChanged.map { Array($0.utf8) }
            firstFlags.fulfill()
        }
        let failed = expectation(description: "offline refresh finished")
        offline.setEvaluationContext(context) { _ in failed.fulfill() }
        wait(for: [firstFlags, failed], timeout: 5)

        for (key, variant) in [(composed, "composed"), (decomposed, "decomposed")] {
            XCTAssertEqual(offline.flagAssignment(for: key)?.variationKey, variant)
            XCTAssertEqual(offline.flagAssignment(for: key)?.reason, "CACHED", variant)
        }
        XCTAssertEqual(keys.wrappedValue.count, 2)
        XCTAssertEqual(Set(keys.wrappedValue), [Array(composed.utf8), Array(decomposed.utf8)])
    }

    /// Breaks if an assignment that collides with another spelling can reject the whole response.
    func testCollidingSpellingWithAnOverflowingNumberKeepsTheOtherFlags() throws {
        // Foundation in Xcode 26 rejects the whole document: "Number 1e400 is not representable in Swift".
        // Later Foundation versions decode it, and this test checks that the other flags stay.
        func decode(_ data: Data) throws -> FlagAssignmentsResponse {
            do {
                return try FlagsNumericJSON.decode(FlagAssignmentsResponse.self, from: data).addingKeySpellings(from: data)
            } catch DecodingError.dataCorrupted(let context)
                where String(describing: context.underlyingError).contains("is not representable") {
                throw XCTSkip("This Foundation rejects a JSON document with an out-of-range number")
            }
        }
        let boolean = #"{"allocationKey":"a","variationKey":"on","variationType":"boolean","variationValue":true,"reason":"STATIC","doLog":true}"#
        let overflow = #"{"allocationKey":"a","variationKey":"big","variationType":"number","variationValue":1e400,"reason":"STATIC","doLog":true}"#
        let other = #"{"allocationKey":"a","variationKey":"other","variationType":"string","variationValue":"x","reason":"STATIC","doLog":true}"#
        // Each spelling as raw UTF-8 bytes or as `\u` escapes.
        let spelled = [(composed, [composed, #"caf\u00e9"#]), (decomposed, [decomposed, #"cafe\u0301"#])]
        for keys in [[composed, decomposed], [decomposed, composed]] {
            for values in [[boolean, overflow], [overflow, boolean]] {
                for (first, second) in [(0, 0), (0, 1), (1, 0), (1, 1)] {
                let label = "\(keys[0].utf8.elementsEqual(composed.utf8) ? "composed" : "decomposed") key first, \(values[0] == boolean ? "boolean" : "number") first, escapes \(first)\(second)"
                let firstKey = spelled.first { $0.0.utf8.elementsEqual(keys[0].utf8) }!.1[first]
                let secondKey = spelled.first { $0.0.utf8.elementsEqual(keys[1].utf8) }!.1[second]
                let body = #"{"data":{"attributes":{"flags":{"\#(firstKey)":\#(values[0]),"\#(secondKey)":\#(values[1]),"other":\#(other)}}}}"#
                let data = Data(body.utf8)
                let response = try decode(data)
                let served = response.flags.map { ($0.key, $0.value) } + response.keySpellings.map { ($0.key, $0.assignment) }
                let booleanKey = values[0] == boolean ? keys[0] : keys[1]
                let numberKey = values[0] == boolean ? keys[1] : keys[0]
                XCTAssertEqual(served.count, 3, label)
                XCTAssertEqual(served.first { $0.0.utf8.elementsEqual(booleanKey.utf8) }?.1.variation(as: Bool.self), true, label)
                let number = try XCTUnwrap(served.first { $0.0.utf8.elementsEqual(numberKey.utf8) }?.1, label)
                XCTAssertNil(number.variation(as: Double.self), label)
                XCTAssertNil(number.variation(as: Int.self), label)
                XCTAssertEqual(response.flags["other"]?.variationKey, "other", label)
                }
            }
        }
    }

    /// Breaks if the numeric or key-spelling scan reads a UTF-16, UTF-32 or byte-order-marked response as UTF-8.
    func testResponsesInOtherUnicodeEncodingsKeepTheirTokensAndSpellings() throws {
        let assignment = { (variant: String, value: String) in
            #"{"allocationKey":"a","variationKey":"\#(variant)","variationType":"number","variationValue":\#(value),"reason":"STATIC","doLog":true}"#
        }
        let body = #"{"data":{"attributes":{"flags":{"caf\#u{00E9}":\#(assignment("composed", "1")),"cafe\u0301":\#(assignment("decomposed", "1.00000000000000001")),"plain":\#(assignment("plain", "1.00000000000000001"))}}}}"#
        let encodings: [(String, Data)] = [
            ("UTF-8 with BOM", Data([0xEF, 0xBB, 0xBF]) + Data(body.utf8)),
            ("UTF-16BE with BOM", Data([0xFE, 0xFF]) + body.data(using: .utf16BigEndian)!),
            ("UTF-16LE with BOM", Data([0xFF, 0xFE]) + body.data(using: .utf16LittleEndian)!),
            ("UTF-16BE", body.data(using: .utf16BigEndian)!),
            ("UTF-16LE", body.data(using: .utf16LittleEndian)!),
            ("UTF-32BE", body.data(using: .utf32BigEndian)!),
            ("UTF-32LE", body.data(using: .utf32LittleEndian)!)
        ]
        for (label, data) in encodings {
            let response = try FlagsNumericJSON.decode(FlagAssignmentsResponse.self, from: data).addingKeySpellings(from: data)
            let served = response.flags.map { ($0.key, $0.value) } + response.keySpellings.map { ($0.key, $0.assignment) }
            XCTAssertEqual(served.count, 3, label)
            XCTAssertEqual(served.first { $0.0.utf8.elementsEqual(composed.utf8) }?.1.variationKey, "composed", label)
            XCTAssertEqual(served.first { $0.0.utf8.elementsEqual(decomposed.utf8) }?.1.variationKey, "decomposed", label)
            let plain = try XCTUnwrap(response.flags["plain"], label)
            XCTAssertNil(plain.variation(as: Int.self), label)
            XCTAssertEqual(plain.variation(as: Double.self), 1, label)
        }
    }
}
