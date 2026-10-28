/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogFlags

final class FlagAssignmentsRequestTests: XCTestCase {
    private let testURL = URL(string: "https://test.example.com/precompute-assignments")!

    func testFlagAssignmentsRequest() throws {
        // Given
        let evaluationContext = FlagsEvaluationContext(
            targetingKey: "user123",
            attributes: [
                "plan": .string("premium"),
                "userId": .string("123")
            ]
        )
        let context = DatadogContext.mockWith(
            clientToken: "test-token",
            env: "production",
            source: "ios",
            sdkVersion: "3.5.1",
            additionalContext: [RUMCoreContext.mockWith(applicationID: "test-app-id")]
        )
        let customHeaders = ["X-Custom-Header": "custom-value"]
        let expectedBody = """
        {
          "data" : {
            "attributes" : {
              "env" : {
                "dd_env" : "production",
                "name" : "production"
              },
              "source" : {
                "sdk_name" : "dd-sdk-ios",
                "sdk_version" : "3.5.1"
              },
              "subject" : {
                "targeting_attributes" : {
                  "plan" : "premium",
                  "userId" : "123"
                },
                "targeting_key" : "user123"
              }
            },
            "type" : "precompute-assignments-request"
          }
        }
        """

        // When
        let request = try URLRequest.flagAssignmentsRequest(
            url: testURL,
            evaluationContext: evaluationContext,
            context: context,
            customHeaders: customHeaders,
            flagSelection: nil
        )

        // Then
        XCTAssertEqual(request.url, testURL)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/vnd.api+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-DD-FEATURE-FLAGS-CAPABILITIES"), "assignment-encoding-flag-key-256-v1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Encoding"), "gzip, deflate, br")
        XCTAssertEqual(request.value(forHTTPHeaderField: "dd-client-token"), "test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "dd-application-id"), "test-app-id")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Custom-Header"), "custom-value")
        let actualBody = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertEqual(actualBody.normalizedJSON, expectedBody.normalizedJSON)
    }

    func testFlagAssignmentsRequestWithFlagSelection() throws {
        // Given
        let flagSelection = CanonicalFlagSelection(tags: ["mobile"], keyPatterns: [])
        let expectedFlagSelection = """
        {
          "key_patterns" : [],
          "tags" : ["mobile"]
        }
        """

        // When
        let request = try URLRequest.flagAssignmentsRequest(
            url: testURL,
            evaluationContext: .mockAny(),
            context: .mockAny(),
            customHeaders: nil,
            flagSelection: flagSelection
        )

        // Then
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let data = try XCTUnwrap(json["data"] as? [String: Any])
        let attributes = try XCTUnwrap(data["attributes"] as? [String: Any])
        let actualFlagSelection = try XCTUnwrap(attributes["flag_selection"])
        let actual = try JSONSerialization.data(withJSONObject: actualFlagSelection)
        XCTAssertEqual(try XCTUnwrap(String(data: actual, encoding: .utf8)).normalizedJSON, expectedFlagSelection.normalizedJSON)
        XCTAssertNotNil(attributes["subject"])
    }

    // MARK: - Flag Selection Canonicalization

    func testNoSelectionOrEmptySelectionIsNotSent() {
        XCTAssertEqual(CanonicalFlagSelection.make(from: nil), .success(nil))
        XCTAssertEqual(CanonicalFlagSelection.make(from: .init()), .success(nil))
        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(tags: ["", " \u{3000}"], keyPatterns: ["\t\n"])), .success(nil))
    }

    func testCanonicalizationTrimsUnicodeWhiteSpaceDropsEmptyValuesAndDedupes() {
        // When
        let result = CanonicalFlagSelection.make(
            from: .init(
                tags: [" mobile ", "mobile", "", "   ", "\u{00A0}team:search\u{3000}", "\u{0085}ui\u{2028}", "\t team:search \n"],
                keyPatterns: ["checkout.*", " checkout.* "]
            )
        )

        // Then
        XCTAssertEqual(result, .success(.init(tags: ["mobile", "team:search", "ui"], keyPatterns: ["checkout.*"])))
    }

    func testCanonicalizationKeepsCharactersOutsideUnicodeWhiteSpace() {
        // When
        let result = CanonicalFlagSelection.make(from: .init(tags: ["\u{FEFF}mobile", "mobile\u{200B}"]))

        // Then
        XCTAssertEqual(result, .success(.init(tags: ["mobile\u{200B}", "\u{FEFF}mobile"], keyPatterns: [])))
    }

    func testCanonicalizationTrimsUnicodeScalarsNotCharacters() {
        // When
        // U+0301 combines with the leading space into one Character.
        let result = CanonicalFlagSelection.make(from: .init(tags: [" \u{0301}x"]))

        // Then
        XCTAssertEqual(result, .success(.init(tags: ["\u{0301}x"], keyPatterns: [])))
    }

    func testCanonicalizationSortsByUTF8Bytes() {
        // When
        let result = CanonicalFlagSelection.make(from: .init(tags: ["\u{1F600}", "\u{FF5E}", "a", "Z"]))

        // Then
        // UTF-16 code unit order would place U+1F600 before U+FF5E.
        XCTAssertEqual(result, .success(.init(tags: ["Z", "a", "\u{FF5E}", "\u{1F600}"], keyPatterns: [])))
    }

    func testCanonicalizationKeepsNFCAndNFDFormsAsDistinctValues() throws {
        // Given
        let nfc = "caf\u{00E9}"
        let nfd = "cafe\u{0301}"
        XCTAssertEqual(nfc, nfd)

        // When
        let selection = try XCTUnwrap(CanonicalFlagSelection.make(from: .init(tags: [nfc, nfd, nfc])).get())

        // Then
        XCTAssertEqual(selection.tags.map { Array($0.utf8) }, [Array(nfd.utf8), Array(nfc.utf8)])
        XCTAssertNotEqual(
            CanonicalFlagSelection(tags: [nfc], keyPatterns: []),
            CanonicalFlagSelection(tags: [nfd], keyPatterns: [])
        )
    }

    func testValueCountLimit() {
        let values31 = (1...31).map { "v\($0)" }
        let values32 = (1...32).map { "v\($0)" }

        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(tags: values31)).map { $0?.tags.count }, .success(31))
        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(tags: values31, keyPatterns: values31)).map { $0?.keyPatterns.count }, .success(31))
        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(tags: values31 + values31 + [" v1 "])).map { $0?.tags.count }, .success(31))
        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(tags: values32)), .failure(.tooManyValues))
        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(keyPatterns: values32)), .failure(.tooManyValues))
        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(tags: ["mobile"], keyPatterns: values32)), .failure(.tooManyValues))
        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(tags: values31, keyPatterns: values32)), .failure(.tooManyValues))
    }

    func testKeyPatternByteLimit() {
        let pattern200 = "*" + String(repeating: "x", count: 199)
        let twoByte200 = String(repeating: "\u{00E9}", count: 100)

        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(keyPatterns: [pattern200])).map { $0?.keyPatterns }, .success([pattern200]))
        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(keyPatterns: ["  \(pattern200)\u{3000}"])).map { $0?.keyPatterns }, .success([pattern200]))
        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(keyPatterns: [twoByte200])).map { $0?.keyPatterns }, .success([twoByte200]))
        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(keyPatterns: [pattern200 + "x"])), .failure(.invalidKeyPattern))
        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(keyPatterns: ["x" + twoByte200])), .failure(.invalidKeyPattern))
    }

    func testTagByteLimit() {
        let tag200 = String(repeating: "a", count: 200)
        let twoByte200 = String(repeating: "\u{00E9}", count: 100)
        // The same 100 Characters in NFD take 300 bytes.
        let decomposed300 = String(repeating: "e\u{0301}", count: 100)

        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(tags: [tag200])).map { $0?.tags }, .success([tag200]))
        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(tags: ["  \(tag200)\u{00A0}"])).map { $0?.tags }, .success([tag200]))
        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(tags: [twoByte200])).map { $0?.tags }, .success([twoByte200]))
        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(tags: [tag200 + "a"])), .failure(.invalidTag))
        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(tags: ["x" + twoByte200])), .failure(.invalidTag))
        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(tags: [decomposed300])), .failure(.invalidTag))
        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(tags: ["mobile", tag200 + "a"])), .failure(.invalidTag))
    }

    func testDropReasonsAreCheckedInOrder() {
        let values32 = (1...32).map { "v\($0)" }
        let tooLong = String(repeating: "a", count: 201)

        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(tags: values32, keyPatterns: [tooLong])), .failure(.tooManyValues))
        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(tags: values32 + [tooLong])), .failure(.tooManyValues))
        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(tags: Array(values32.prefix(31)) + [tooLong])), .failure(.tooManyValues))
        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(tags: [tooLong], keyPatterns: [tooLong])), .failure(.invalidKeyPattern))
    }

    func testDroppedSelectionLogsOneErrorAndOneTelemetryEventWithTheReasonOnly() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        let telemetry = TelemetryMock()
        let secret = "secret-tag"

        // When
        let resolved = CanonicalFlagSelection.resolve(
            .init(tags: [secret] + (1...31).map { "v\($0)" }),
            telemetry: telemetry
        )

        // Then
        XCTAssertNil(resolved)
        XCTAssertEqual(dd.logger.errorMessages.count, 1)
        XCTAssertEqual(
            dd.logger.errorMessages.first,
            "`Flags.Configuration.flagSelection` was not sent (too_many_values: each list accepts at most 31 values). Loading the full flag configuration."
        )
        XCTAssertEqual(telemetry.messages.count, 1)
        let debug = try XCTUnwrap(telemetry.messages.firstDebug())
        XCTAssertEqual(debug.message, "Flag selection dropped")
        XCTAssertEqual(debug.attributes?.count, 1)
        XCTAssertEqual(debug.attributes?["reason"] as? String, "too_many_values")
        XCTAssertFalse(telemetry.description.contains(secret))
    }

    func testValidSelectionLogsNothing() {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        let telemetry = TelemetryMock()

        // When
        let resolved = CanonicalFlagSelection.resolve(.init(tags: ["mobile"]), telemetry: telemetry)

        // Then
        XCTAssertEqual(resolved, CanonicalFlagSelection(tags: ["mobile"], keyPatterns: []))
        XCTAssertTrue(dd.logger.errorMessages.isEmpty)
        XCTAssertTrue(telemetry.messages.isEmpty)
    }

    // MARK: - Shared Flag Selection Vectors

    func testSharedFlagSelectionVectors() {
        XCTAssertEqual(sharedFlagSelectionVectors.count, 38)

        for vector in sharedFlagSelectionVectors {
            XCTAssertEqual(
                CanonicalFlagSelection.make(from: .init(tags: vector.tags, keyPatterns: vector.keyPatterns)),
                vector.expected,
                vector.name
            )
        }
    }
}

// MARK: - Shared Flag Selection Vectors

private struct FlagSelectionVector {
    let name: String
    let tags: [String]
    let keyPatterns: [String]
    let expected: Result<CanonicalFlagSelection?, FlagSelectionDropReason>
}

private func numbered(_ prefix: String, _ count: Int) -> [String] {
    (1...count).map { prefix + String(format: "%02d", $0) }
}

/// Every case with an `sdk` expectation in the flag selection vectors shared by all SDKs and servers:
/// https://github.com/DataDog/ffe-system-test-data/blob/e8777633d09f0e42b082f5ed64d42edeed080220/flag-selection/selection-vectors.json
/// The input is the case's `query`, in order and before trimming. The `rawQuery` cases cover URL decoding and malformed input,
/// which the typed Swift API cannot express, so they are not ported.
private let sharedFlagSelectionVectors: [FlagSelectionVector] = [
        .init(
            name: "no parameters selects every flag",
            tags: [],
            keyPatterns: [],
            expected: .success(nil)
        ),
        .init(
            name: "tag selects flags having any of the tags",
            tags: ["team:search", "mobile"],
            keyPatterns: [],
            expected: .success(.init(tags: ["mobile", "team:search"], keyPatterns: []))
        ),
        .init(
            name: "tags and key patterns are combined with OR",
            tags: ["mobile"],
            keyPatterns: ["checkout.*"],
            expected: .success(.init(tags: ["mobile"], keyPatterns: ["checkout.*"]))
        ),
        .init(
            name: "key pattern must match the whole key",
            tags: [],
            keyPatterns: ["checkout"],
            expected: .success(.init(tags: [], keyPatterns: ["checkout"]))
        ),
        .init(
            name: "key pattern without a star selects exactly that key",
            tags: [],
            keyPatterns: ["checkout.new-flow"],
            expected: .success(.init(tags: [], keyPatterns: ["checkout.new-flow"]))
        ),
        .init(
            name: "star matches an empty run and multiple stars are allowed",
            tags: [],
            keyPatterns: ["*search*auto*complete*"],
            expected: .success(.init(tags: [], keyPatterns: ["*search*auto*complete*"]))
        ),
        .init(
            name: "leading star",
            tags: [],
            keyPatterns: ["*-v2"],
            expected: .success(.init(tags: [], keyPatterns: ["*-v2"]))
        ),
        .init(
            name: "lone star matches every key",
            tags: [],
            keyPatterns: ["*"],
            expected: .success(.init(tags: [], keyPatterns: ["*"]))
        ),
        .init(
            name: "question mark and brackets are literal",
            tags: [],
            keyPatterns: ["search.ranking-v?", "[a]*", "{a,b}"],
            expected: .success(.init(tags: [], keyPatterns: ["[a]*", "search.ranking-v?", "{a,b}"]))
        ),
        .init(
            name: "braces are literal even when an alternative names a flag",
            tags: [],
            keyPatterns: ["{mobile.dark-mode,missing}"],
            expected: .success(.init(tags: [], keyPatterns: ["{mobile.dark-mode,missing}"]))
        ),
        .init(
            name: "tags are never globs",
            tags: ["team:*"],
            keyPatterns: [],
            expected: .success(.init(tags: ["team:*"], keyPatterns: []))
        ),
        .init(
            name: "tags match case-sensitively",
            tags: ["Team:Payments", "MOBILE"],
            keyPatterns: [],
            expected: .success(.init(tags: ["MOBILE", "Team:Payments"], keyPatterns: []))
        ),
        .init(
            name: "key patterns match case-sensitively",
            tags: [],
            keyPatterns: ["CHECKOUT.*", "Mobile.Dark-Mode"],
            expected: .success(.init(tags: [], keyPatterns: ["CHECKOUT.*", "Mobile.Dark-Mode"]))
        ),
        .init(
            name: "values are trimmed, empties dropped and duplicates removed",
            tags: [" mobile ", "mobile", "", "   "],
            keyPatterns: [],
            expected: .success(.init(tags: ["mobile"], keyPatterns: []))
        ),
        .init(
            name: "lists that are empty after normalization select every flag",
            tags: ["", "   "],
            keyPatterns: [" "],
            expected: .success(nil)
        ),
        .init(
            name: "values are trimmed of Unicode white space",
            tags: ["\u{00A0}mobile\u{3000}", "\u{0085}ui\u{2028}", "\u{0009} team:search \u{000A}"],
            keyPatterns: [],
            expected: .success(.init(tags: ["mobile", "team:search", "ui"], keyPatterns: []))
        ),
        .init(
            name: "characters outside Unicode White_Space are not trimmed",
            tags: ["\u{FEFF}mobile", "mobile\u{200B}"],
            keyPatterns: [],
            expected: .success(.init(tags: ["mobile\u{200B}", "\u{FEFF}mobile"], keyPatterns: []))
        ),
        .init(
            name: "values sort by UTF-8 bytes",
            tags: ["\u{1F600}", "\u{FF5E}", "a", "Z"],
            keyPatterns: [],
            expected: .success(.init(tags: ["Z", "a", "\u{FF5E}", "\u{1F600}"], keyPatterns: []))
        ),
        .init(
            name: "partial match serves only the matching flags",
            tags: ["mobile", "missing"],
            keyPatterns: ["nothing.*"],
            expected: .success(.init(tags: ["missing", "mobile"], keyPatterns: ["nothing.*"]))
        ),
        .init(
            name: "31 values in one list are allowed",
            tags: numbered("t", 31),
            keyPatterns: [],
            expected: .success(.init(tags: numbered("t", 31), keyPatterns: []))
        ),
        .init(
            name: "32 values in one list are rejected",
            tags: [],
            keyPatterns: numbered("k", 32),
            expected: .failure(.tooManyValues)
        ),
        .init(
            name: "31 values in each list are allowed",
            tags: numbered("t", 31),
            keyPatterns: numbered("p", 31),
            expected: .success(.init(tags: numbered("t", 31), keyPatterns: numbered("p", 31)))
        ),
        .init(
            name: "32 values in one list are rejected even when the other is within the limit",
            tags: numbered("t", 31),
            keyPatterns: numbered("p", 32),
            expected: .failure(.tooManyValues)
        ),
        .init(
            name: "duplicates do not count toward the limit",
            tags: numbered("t", 31) + ["t01", " t02 "],
            keyPatterns: [],
            expected: .success(.init(tags: numbered("t", 31), keyPatterns: []))
        ),
        .init(
            name: "key pattern of 200 bytes is allowed",
            tags: [],
            keyPatterns: ["*" + String(repeating: "x", count: 199)],
            expected: .success(.init(tags: [], keyPatterns: ["*" + String(repeating: "x", count: 199)]))
        ),
        .init(
            name: "key pattern of 201 bytes is invalid",
            tags: [],
            keyPatterns: ["*" + String(repeating: "x", count: 200)],
            expected: .failure(.invalidKeyPattern)
        ),
        .init(
            name: "key pattern length is measured after trimming",
            tags: [],
            keyPatterns: ["  *" + String(repeating: "x", count: 199) + "  "],
            expected: .success(.init(tags: [], keyPatterns: ["*" + String(repeating: "x", count: 199)]))
        ),
        .init(
            name: "key pattern length counts UTF-8 bytes: 100 two-byte characters are allowed",
            tags: [],
            keyPatterns: [String(repeating: "\u{00E9}", count: 100)],
            expected: .success(.init(tags: [], keyPatterns: [String(repeating: "\u{00E9}", count: 100)]))
        ),
        .init(
            name: "key pattern length counts UTF-8 bytes: 201 bytes are invalid",
            tags: [],
            keyPatterns: ["x" + String(repeating: "\u{00E9}", count: 100)],
            expected: .failure(.invalidKeyPattern)
        ),
        .init(
            name: "tag of 200 bytes is allowed",
            tags: [String(repeating: "a", count: 200)],
            keyPatterns: [],
            expected: .success(.init(tags: [String(repeating: "a", count: 200)], keyPatterns: []))
        ),
        .init(
            name: "tag of 201 bytes is invalid",
            tags: [String(repeating: "a", count: 201)],
            keyPatterns: [],
            expected: .failure(.invalidTag)
        ),
        .init(
            name: "tag length is measured after trimming",
            tags: ["  " + String(repeating: "a", count: 200) + "  "],
            keyPatterns: [],
            expected: .success(.init(tags: [String(repeating: "a", count: 200)], keyPatterns: []))
        ),
        .init(
            name: "tag length counts UTF-8 bytes: 100 two-byte characters are allowed",
            tags: [String(repeating: "\u{00E9}", count: 100)],
            keyPatterns: [],
            expected: .success(.init(tags: [String(repeating: "\u{00E9}", count: 100)], keyPatterns: []))
        ),
        .init(
            name: "tag length counts UTF-8 bytes: 201 bytes are invalid",
            tags: ["x" + String(repeating: "\u{00E9}", count: 100)],
            keyPatterns: [],
            expected: .failure(.invalidTag)
        ),
        .init(
            name: "a long tag invalidates the selection even when other tags match",
            tags: ["mobile", String(repeating: "a", count: 201)],
            keyPatterns: [],
            expected: .failure(.invalidTag)
        ),
        .init(
            name: "too_many_values takes precedence over invalid_key_pattern",
            tags: numbered("t", 32),
            keyPatterns: ["*" + String(repeating: "x", count: 200)],
            expected: .failure(.tooManyValues)
        ),
        .init(
            name: "too_many_values takes precedence over invalid_tag",
            tags: numbered("t", 31) + [String(repeating: "a", count: 201)],
            keyPatterns: [],
            expected: .failure(.tooManyValues)
        ),
        .init(
            name: "invalid_key_pattern takes precedence over invalid_tag",
            tags: [String(repeating: "a", count: 201)],
            keyPatterns: [String(repeating: "a", count: 201)],
            expected: .failure(.invalidKeyPattern)
        ),
]

// MARK: - Test Helpers

extension String {
    fileprivate var normalizedJSON: String {
        // Normalizes JSON string by parsing and re-serializing with sorted keys and pretty printing.
        // This allows for comparing JSON content regardless of formatting or key ordering.
        guard let data = self.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let normalized = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .prettyPrinted]),
              let result = String(data: normalized, encoding: .utf8) else {
            return self
        }
        return result
    }
}
