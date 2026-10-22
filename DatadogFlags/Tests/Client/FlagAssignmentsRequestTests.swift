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
        XCTAssertEqual(CanonicalFlagSelection.make(from: .init(tags: ["mobile"], keyPatterns: values32)), .failure(.tooManyValues))
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
}

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
