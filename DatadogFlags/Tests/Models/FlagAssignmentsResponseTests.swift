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
            return try JSONDecoder().decode(FlagAssignment.self, from: json)
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
            let decoder = JSONDecoder()
            decoder.userInfo[try XCTUnwrap(CodingUserInfoKey.decodesStoredVariations)] = true
            return try decoder.decode(FlagAssignment.self, from: JSONEncoder().encode(assignment))
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

        // A Double converts to Int only within +/-(2^53 - 1), where it represents every integer exactly
        #if _pointerBitWidth(_64)
        XCTAssertEqual(built(.double(9_007_199_254_740_991)).variation(as: Int.self), 9_007_199_254_740_991)
        XCTAssertEqual(built(.double(-9_007_199_254_740_991)).variation(as: Int.self), -9_007_199_254_740_991)
        #endif
        XCTAssertNil(built(.double(9_007_199_254_740_992)).variation(as: Int.self))
        XCTAssertNil(built(.double(-9_007_199_254_740_992)).variation(as: Int.self))
        XCTAssertNil(built(.double(1e20)).variation(as: Int.self))
        XCTAssertNil(built(.double(.infinity)).variation(as: Int.self))
        XCTAssertNil(built(.double(.nan)).variation(as: Int.self))

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

final class SplitFeatureParsingTests: XCTestCase {
    private func decodeFlag(features: String?) throws -> FlagAssignment {
        let field = features.map { #","features":\#($0)"# } ?? ""
        let json = """
            {"data":{"attributes":{"flags":{"flag":{
                "allocationKey":"allocation","variationKey":"on","variationType":"boolean",
                "variationValue":true,"reason":"TARGETING_MATCH","doLog":true\(field)
            }}}}}
            """
        let response = try JSONDecoder().decode(FlagAssignmentsResponse.self, from: Data(json.utf8))
        return try XCTUnwrap(response.flags["flag"], "the flag must survive any `features` value")
    }

    func testFeaturesWithMixedValueTypesParse() throws {
        let assignment = try decodeFlag(features: """
            [
                {"key":"holdout.key","value":"h-1","destinations":["HOOK"]},
                {"key":"holdout.should_include_in_holdout_analysis","value":false,"destinations":["HOOK","EXPOSURE"]},
                {"key":"weight","value":2,"destinations":["EVALUATION"]},
                {"key":"ratio","value":0.25,"destinations":["FUTURE","HOOK"]}
            ]
            """)

        XCTAssertEqual(assignment.features, [
            SplitFeature(key: "holdout.key", value: .string("h-1"), destinations: ["HOOK"]),
            SplitFeature(key: "holdout.should_include_in_holdout_analysis", value: .bool(false), destinations: ["HOOK", "EXPOSURE"]),
            SplitFeature(key: "weight", value: .double(2), destinations: ["EVALUATION"]),
            SplitFeature(key: "ratio", value: .double(0.25), destinations: ["FUTURE", "HOOK"]),
        ])
    }

    func testMalformedOrMissingFeaturesNeverFailTheFlag() throws {
        for features in [nil, "null", "{}", #""HOOK""#, "1", "true", "[]", #"{"key":"k","value":"v","destinations":["HOOK"]}"#] {
            XCTAssertEqual(try decodeFlag(features: features).features, [], features ?? "missing")
        }
    }

    func testInvalidEntriesAreSkippedAndValidOnesKept() throws {
        let invalid = [
            "null", "1", #""text""#, "[]",
            #"{"value":"v","destinations":["HOOK"]}"#,
            #"{"key":"","value":"v","destinations":["HOOK"]}"#,
            #"{"key":7,"value":"v","destinations":["HOOK"]}"#,
            #"{"key":"k","destinations":["HOOK"]}"#,
            #"{"key":"k","value":null,"destinations":["HOOK"]}"#,
            #"{"key":"k","value":{"a":1},"destinations":["HOOK"]}"#,
            #"{"key":"k","value":["a"],"destinations":["HOOK"]}"#,
            #"{"key":"k","value":"v"}"#,
            #"{"key":"k","value":"v","destinations":"HOOK"}"#,
            #"{"key":"k","value":"v","destinations":[]}"#,
            #"{"key":"k","value":"v","destinations":[1,null,"",{}]}"#,
        ]
        for entry in invalid {
            let assignment = try decodeFlag(features: """
                [\(entry),{"key":"valid","value":"v","destinations":["HOOK"]}]
                """)
            XCTAssertEqual(assignment.features, [SplitFeature(key: "valid", value: .string("v"), destinations: ["HOOK"])], entry)
        }
    }

    func testInvalidDestinationNamesAreDroppedFromAValidFeature() throws {
        let assignment = try decodeFlag(features: #"[{"key":"k","value":"v","destinations":[null,"HOOK",3,"","EXPOSURE"]}]"#)
        XCTAssertEqual(assignment.features, [SplitFeature(key: "k", value: .string("v"), destinations: ["HOOK", "EXPOSURE"])])
    }

    func testFirstValidFeatureWinsOnARepeatedKey() throws {
        let assignment = try decodeFlag(features: """
            [
                {"key":"holdout.key","value":null,"destinations":["HOOK"]},
                {"key":"holdout.key","value":"first","destinations":["HOOK"]},
                {"key":"holdout.key","value":"second","destinations":["HOOK","EXPOSURE","EVALUATION"]}
            ]
            """)
        XCTAssertEqual(assignment.features, [SplitFeature(key: "holdout.key", value: .string("first"), destinations: ["HOOK"])])
        XCTAssertEqual(assignment.features.values(for: .exposure), [:])
        XCTAssertEqual(assignment.features.values(for: .evaluation), [:])
    }

    func testFeaturesArePersistedWithCachedAssignments() throws {
        var assignment = FlagAssignment.mockAnyBoolean()
        assignment.features = [
            SplitFeature(key: "holdout.key", value: .string("h-1"), destinations: ["HOOK"]),
            SplitFeature(key: "weight", value: .double(1.5), destinations: ["EVALUATION", "FUTURE"]),
            SplitFeature(key: "flag", value: .bool(true), destinations: ["EXPOSURE"]),
        ]
        let data = FlagsData(flags: ["flag": assignment], context: .mockAny(), date: .mockAny())

        let decoded = try JSONDecoder().decode(FlagsData.self, from: JSONEncoder().encode(data))

        XCTAssertEqual(decoded.flags["flag"]?.features, assignment.features)
        XCTAssertNotEqual(FlagAssignment.mockAnyBoolean(), assignment, "features are part of the cached assignment")
    }

    func testRoutingUsesOnlyKnownDestinations() {
        let features = [
            SplitFeature(key: "hook", value: .string("h"), destinations: ["HOOK"]),
            SplitFeature(key: "exposure", value: .double(1), destinations: ["EXPOSURE"]),
            SplitFeature(key: "evaluation", value: .bool(true), destinations: ["EVALUATION"]),
            SplitFeature(key: "nowhere", value: .string("n"), destinations: ["FUTURE", "hook"]),
        ]
        XCTAssertEqual(features.values(for: .hook), ["hook": .string("h")])
        XCTAssertEqual(features.values(for: .exposure), ["exposure": .double(1)])
        XCTAssertEqual(features.values(for: .evaluation), ["evaluation": .bool(true)])
        XCTAssertEqual(features.hookMetadata(), ["__dd_feature.hook": .string("h")])
        XCTAssertEqual([SplitFeature]().hookMetadata(), [:])
    }

    func testUnknownDestinationsAreWarnedOncePerNameUpToTheCap() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        let warnings = UnknownFeatureDestinationWarnings()
        func flags(_ names: [String]) -> [String: FlagAssignment] {
            var assignment = FlagAssignment.mockAnyBoolean()
            assignment.features = [SplitFeature(key: "k", value: .string("v"), destinations: names)]
            return ["flag": assignment]
        }

        warnings.warn(about: flags(["HOOK", "EXPOSURE", "EVALUATION"]))
        XCTAssertEqual(dd.logger.warnMessages.count, 0)

        warnings.warn(about: flags(["FUTURE", "HOOK"]))
        warnings.warn(about: flags(["FUTURE"]))
        XCTAssertEqual(dd.logger.warnMessages.count, 1)
        XCTAssertTrue(dd.logger.warnMessages[0].contains("FUTURE"))

        warnings.warn(about: flags((0..<100).map { "UNKNOWN_\($0)" }))
        XCTAssertEqual(dd.logger.warnMessages.count, UnknownFeatureDestinationWarnings.maxWarnedNames)
    }

    func testFetcherWarnsAboutUnknownDestinations() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        let bytes = Data("""
            {"data":{"attributes":{"flags":{"flag":{
                "allocationKey":"a","variationKey":"on","variationType":"boolean","variationValue":true,
                "reason":"TARGETING_MATCH","doLog":true,
                "features":[{"key":"k","value":"v","destinations":["FUTURE"]}]
            }}}}}
            """.utf8)
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            flagSelection: nil,
            featureScope: FeatureScopeMock(),
            fetch: { _, complete in complete(.success((bytes, .mockAny()))) }
        )
        for _ in 0..<2 {
            let completed = expectation(description: "fetched")
            fetcher.flagAssignments(for: .mockAny()) { _ in completed.fulfill() }
            wait(for: [completed], timeout: 1)
        }
        XCTAssertEqual(dd.logger.warnMessages.filter { $0.contains("FUTURE") }.count, 1)
    }
}

final class SnapshotFeatureBridgeTests: XCTestCase {
    private func decodedAssignment() throws -> FlagAssignment {
        let json = """
            {"data":{"attributes":{"observeFullEvaluationData":true,"flags":{"flag":{
                "allocationKey":"allocation","variationKey":"on","variationType":"boolean",
                "variationValue":true,"reason":"TARGETING_MATCH","doLog":true,"serialId":0,
                "features":[
                    {"key":"holdout.should_include_in_holdout_analysis","value":false,"destinations":["HOOK"]},
                    {"key":"weight","value":2026,"destinations":["EXPOSURE","EVALUATION"]},
                    {"key":"holdout.key","value":"2026","destinations":["HOOK","FUTURE"]}
                ]
            }}}}}
            """
        let response = try JSONDecoder().decode(FlagAssignmentsResponse.self, from: Data(json.utf8))
        return try XCTUnwrap(response.flags["flag"])
    }

    private func rebuilt(_ assignment: FlagAssignment, serialID: Int?) -> FlagAssignment {
        FlagAssignment(
            allocationKey: assignment.allocationKey,
            variationKey: assignment.variationKey,
            variation: assignment.variation,
            reason: assignment.reason,
            doLog: assignment.doLog,
            serialID: serialID,
            observeFullEvaluationData: assignment.observeFullEvaluationData,
            snapshotFeatures: assignment.snapshotFeatures
        )
    }

    func testSnapshotFeaturesRoundTripThroughTheBridgeInitializer() throws {
        let native = try decodedAssignment()

        XCTAssertEqual(native.snapshotFeatures, [
            FlagSnapshotFeature(key: "holdout.should_include_in_holdout_analysis", value: .bool(false), destinations: ["HOOK"]),
            FlagSnapshotFeature(key: "weight", value: .number(2_026), destinations: ["EXPOSURE", "EVALUATION"]),
            FlagSnapshotFeature(key: "holdout.key", value: .string("2026"), destinations: ["HOOK", "FUTURE"]),
        ])
        XCTAssertEqual(rebuilt(native, serialID: 0), native)
        XCTAssertTrue(rebuilt(native, serialID: 0).observeFullEvaluationData)

        for serialID in [nil, 0, Int.max] {
            var expected = native
            expected.serialID = serialID
            XCTAssertEqual(rebuilt(expected, serialID: serialID), expected, "serial ID \(String(describing: serialID))")
        }

        var protected = native
        protected.observeFullEvaluationData = false
        XCTAssertFalse(rebuilt(protected, serialID: 0).observeFullEvaluationData)
    }

    func testBridgeInitializerNormalizesFeaturesLikeDecoding() {
        let assignment = FlagAssignment(
            allocationKey: "allocation",
            variationKey: "on",
            variation: .boolean(true),
            reason: "TARGETING_MATCH",
            doLog: true,
            serialID: nil,
            observeFullEvaluationData: false,
            snapshotFeatures: [
                FlagSnapshotFeature(key: "", value: .string("no key"), destinations: ["HOOK"]),
                FlagSnapshotFeature(key: "k", value: .number(.nan), destinations: ["HOOK"]),
                FlagSnapshotFeature(key: "k", value: .number(.infinity), destinations: ["HOOK"]),
                FlagSnapshotFeature(key: "k", value: .string("no destination"), destinations: ["", ""]),
                FlagSnapshotFeature(key: "k", value: .string("first"), destinations: ["", "HOOK", "FUTURE"]),
                FlagSnapshotFeature(key: "k", value: .bool(true), destinations: ["EXPOSURE"]),
                FlagSnapshotFeature(key: "n", value: .number(-0.5), destinations: ["EVALUATION"]),
            ]
        )

        XCTAssertEqual(assignment.features, [
            SplitFeature(key: "k", value: .string("first"), destinations: ["HOOK", "FUTURE"]),
            SplitFeature(key: "n", value: .double(-0.5), destinations: ["EVALUATION"]),
        ])
        XCTAssertEqual(assignment.features.values(for: .hook), ["k": .string("first")])
        XCTAssertEqual(assignment.features.values(for: .exposure), [:])
        XCTAssertEqual(assignment.features.values(for: .evaluation), ["n": .double(-0.5)])
    }

    func testPublicInitializerBuildsNoFeaturesAndProtectedConsent() {
        let assignment = FlagAssignment(allocationKey: "a", variationKey: "v", variation: .boolean(true), reason: "STATIC", doLog: true)

        XCTAssertEqual(assignment.features, [])
        XCTAssertEqual(assignment.snapshotFeatures, [])
        XCTAssertFalse(assignment.observeFullEvaluationData)
    }
}
