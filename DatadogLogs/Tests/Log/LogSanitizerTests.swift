/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogLogs

class LogSanitizerTests: XCTestCase {
    /// Tracer Attributes shared with other Feature registered in core.
    struct TracerAttributes {
        static let traceID = "dd.trace_id"
        static let spanID = "dd.span_id"
    }

    /// RUM Attributes shared with other Feature registered in core.
    enum RUMContextAttributes {
        enum IDs {
            /// The ID of RUM application (`String`).
            static let applicationID = "application_id"
            /// The ID of current RUM session (standard UUID `String`, lowercased).
            /// In case the session is rejected (not sampled), RUM context is set to empty (`[:]`) in core.
            static let sessionID = "session_id"
            /// The ID of current RUM view (standard UUID `String`, lowercased).
            static let viewID = "view.id"
            /// The ID of current RUM action (standard UUID `String`, lowercased).
            static let userActionID = "user_action.id"
        }
    }

    // MARK: - Attributes sanitization

    func testWhenUserAttributeUsesReservedName_itIsIgnored() {
        let log = LogEvent.mockWith(
            attributes: .mockWith(
                userAttributes: [
                    // reserved attributes:
                    "host": mockValue(),
                    "message": mockValue(),
                    "status": mockValue(),
                    "service": mockValue(),
                    "build_id": mockValue(),
                    "source": mockValue(),
                    "ddtags": mockValue(),

                    // valid attributes:
                    "error.kind": mockValue(),
                    "error.message": mockValue(),
                    "error.stack": mockValue(),
                    "attribute1": mockValue(),
                    "attribute2": mockValue(),
                    "date": mockValue(),
                ]
            )
        )

        let sanitized = LogEventSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.attributes.userAttributes.count, 6)
        XCTAssertNotNil(sanitized.attributes.userAttributes["attribute1"])
        XCTAssertNotNil(sanitized.attributes.userAttributes["attribute2"])
        XCTAssertNotNil(sanitized.attributes.userAttributes["date"])
    }

    func testWhenUserAttributeNameExceeds20NestedLevels_itIsEscapedByUnderscore() {
        let log = LogEvent.mockWith(
            attributes: .mockWith(
                userAttributes: [
                    // 20 segments = 19 dots — must NOT be escaped
                    "one.two.three.four.five.six.seven.eight.nine.ten.eleven.twelve.thirteen.fourteen.fifteen.sixteen.seventeen.eighteen.nineteen.twenty": mockValue(),
                    // 21 segments = 20 dots — 20th dot MUST be escaped to "_"
                    "one.two.three.four.five.six.seven.eight.nine.ten.eleven.twelve.thirteen.fourteen.fifteen.sixteen.seventeen.eighteen.nineteen.twenty.twentyone": mockValue(),
                    // 22 segments = 21 dots — both 20th and 21st dots escaped
                    "one.two.three.four.five.six.seven.eight.nine.ten.eleven.twelve.thirteen.fourteen.fifteen.sixteen.seventeen.eighteen.nineteen.twenty.twentyone.twentytwo": mockValue(),
                ]
            )
        )

        let sanitized = LogEventSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.attributes.userAttributes.count, 3)
        // 19 dots — untouched
        XCTAssertNotNil(sanitized.attributes.userAttributes[
            "one.two.three.four.five.six.seven.eight.nine.ten.eleven.twelve.thirteen.fourteen.fifteen.sixteen.seventeen.eighteen.nineteen.twenty"
        ])
        // 20 dots — 20th dot escaped
        XCTAssertNotNil(sanitized.attributes.userAttributes[
            "one.two.three.four.five.six.seven.eight.nine.ten.eleven.twelve.thirteen.fourteen.fifteen.sixteen.seventeen.eighteen.nineteen.twenty_twentyone"
        ])
        // 21 dots — both 20th and 21st dots escaped
        XCTAssertNotNil(sanitized.attributes.userAttributes[
            "one.two.three.four.five.six.seven.eight.nine.ten.eleven.twelve.thirteen.fourteen.fifteen.sixteen.seventeen.eighteen.nineteen.twenty_twentyone_twentytwo"
        ])
    }

    func testWhenUserAttributeNameIsInvalid_itIsIgnored() {
        let log = LogEvent.mockWith(
            attributes: .mockWith(
                userAttributes: [
                    "valid-name": mockValue(),
                    "": mockValue(), // invalid name
                ]
            )
        )

        let sanitized = LogEventSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.attributes.userAttributes.count, 1)
        XCTAssertNotNil(sanitized.attributes.userAttributes["valid-name"])
    }

    func testWhenNumberOfUserAttributesExceedsLimit_itDropsExtraOnes() {
        let mockAttributes = (0...1_000).map { index in ("attribute-\(index)", mockValue()) }
        let log = LogEvent.mockWith(
            attributes: .mockWith(
                userAttributes: Dictionary(uniqueKeysWithValues: mockAttributes)
            )
        )

        let sanitized = LogEventSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.attributes.userAttributes.count, AttributesSanitizer.Constraints.maxNumberOfAttributes)
    }

    func testInternalAttributesAreNotSanitized() {
        let log = LogEvent.mockWith(
            attributes: .mockWith(
                internalAttributes: [
                    TracerAttributes.traceID: mockValue(),
                    TracerAttributes.spanID: mockValue(),
                    "attribute3": mockValue(),
                ]
            )
        )

        let sanitized = LogEventSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.attributes.internalAttributes?.count, 3)
    }

    func testReservedAttributesAreSanitized() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let log = LogEvent.mockWith(
            attributes: .mockWith(
                userAttributes: [
                    TracerAttributes.traceID: mockValue(),
                    TracerAttributes.spanID: mockValue(),
                    RUMContextAttributes.IDs.applicationID: mockValue(),
                    RUMContextAttributes.IDs.sessionID: mockValue(),
                    RUMContextAttributes.IDs.viewID: mockValue(),
                    RUMContextAttributes.IDs.userActionID: mockValue(),
                    "attribute3": mockValue(),
                ]
            )
        )

        let sanitized = LogEventSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.attributes.userAttributes.count, 1)
        let logs = dd.logger.errorLogs
        XCTAssertEqual(logs.count, 6)
        dd.logger.errorLogs.forEach {
            XCTAssertTrue($0.message.matches(regex: "'.*' is a reserved attribute name. This attribute will be ignored."))
        }
    }

    func testWhenAttributeValueExceeds25600Characters_itIsTruncated() {
        let longValue = String(repeating: "a", count: 25_601)
        let log = LogEvent.mockWith(
            attributes: .mockWith(userAttributes: ["key": longValue])
        )

        let sanitized = LogEventSanitizer().sanitize(log: log)

        let value = sanitized.attributes.userAttributes["key"] as? String
        XCTAssertEqual(value?.count, 25_600)
    }

    func testWhenAttributeValueIsWithinLimit_itIsNotModified() {
        let value = String(repeating: "a", count: 25_600)
        let log = LogEvent.mockWith(
            attributes: .mockWith(userAttributes: ["key": value])
        )

        let sanitized = LogEventSanitizer().sanitize(log: log)

        let result = sanitized.attributes.userAttributes["key"] as? String
        XCTAssertEqual(result?.count, 25_600)
    }

    // MARK: - Tags sanitization

    func testWhenTagHasUpperCasedCharacters_itGetsLowerCased() {
        let log = LogEvent.mockWith(
            tags: ["abcd", "Abcdef:ghi", "ABCDEF:GHIJK", "ABCDEFGHIJK"]
        )

        let sanitized = LogEventSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.tags, ["abcd", "abcdef:ghi", "abcdef:ghijk", "abcdefghijk"])
    }

    func testWhenTagStartsWithIllegalCharacter_itIsIgnored() {
        let log = LogEvent.mockWith(
            tags: ["?invalid", "valid", "&invalid", ".abcdefghijk", ":abcd"]
        )

        let sanitized = LogEventSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.tags, ["valid"])
    }

    func testWhenTagContainsIllegalCharacter_itIsConvertedToUnderscore() {
        let log = LogEvent.mockWith(
            tags: ["this&needs&underscore", "this*as*well", "this/doesnt", "tag with whitespaces"]
        )

        let sanitized = LogEventSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.tags, ["this_needs_underscore", "this_as_well", "this/doesnt", "tag_with_whitespaces"])
    }

    func testWhenTagContainsTrailingCommas_itItTruncatesThem() {
        let log = LogEvent.mockWith(
            tags: ["with-one-comma:", "with-several-commas::::", "with-comma:in-the-middle"]
        )

        let sanitized = LogEventSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.tags, ["with-one-comma", "with-several-commas", "with-comma:in-the-middle"])
    }

    func testWhenTagExceedsLengthLimit_itIsTruncated() {
        let log = LogEvent.mockWith(
            tags: [.mockRepeating(character: "a", times: 2 * LogEventSanitizer.Constraints.maxTagLength)]
        )

        let sanitized = LogEventSanitizer().sanitize(log: log)

        XCTAssertEqual(
            sanitized.tags,
            [.mockRepeating(character: "a", times: LogEventSanitizer.Constraints.maxTagLength)]
        )
    }

    func testWhenTagUsesReservedKey_itIsIgnored() {
        let log = LogEvent.mockWith(
            tags: ["host:abc", "device:abc", "source:abc", "service:abc", "valid"]
        )

        let sanitized = LogEventSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.tags, ["valid"])
    }

    func testWhenNumberOfTagsExceedsLimit_itDropsExtraOnes() {
        let mockTags = (0...1_000).map { index in "tag\(index)" }
        let log = LogEvent.mockWith(
            tags: mockTags
        )

        let sanitized = LogEventSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.tags?.count, LogEventSanitizer.Constraints.maxNumberOfTags)
    }

    // MARK: - Private

    private func mockValue() -> String {
        return .mockAny()
    }
}
