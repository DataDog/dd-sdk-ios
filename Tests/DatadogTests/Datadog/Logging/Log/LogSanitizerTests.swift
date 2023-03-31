/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class LogSanitizerTests: XCTestCase {
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

    func testWhenUserAttributeNameExceeds10NestedLevels_itIsEscapedByUnderscore() {
        let log = LogEvent.mockWith(
            attributes: .mockWith(
                userAttributes: [
                    "one": mockValue(),
                    "one.two": mockValue(),
                    "one.two.three": mockValue(),
                    "one.two.three.four": mockValue(),
                    "one.two.three.four.five": mockValue(),
                    "one.two.three.four.five.six": mockValue(),
                    "one.two.three.four.five.six.seven": mockValue(),
                    "one.two.three.four.five.six.seven.eight": mockValue(),
                    "one.two.three.four.five.six.seven.eight.nine": mockValue(),
                    "one.two.three.four.five.six.seven.eight.nine.ten": mockValue(),
                    "one.two.three.four.five.six.seven.eight.nine.ten.eleven": mockValue(),
                    "one.two.three.four.five.six.seven.eight.nine.ten.eleven.twelve": mockValue(),
                ]
            )
        )

        let sanitized = LogEventSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.attributes.userAttributes.count, 12)
        XCTAssertNotNil(sanitized.attributes.userAttributes["one"])
        XCTAssertNotNil(sanitized.attributes.userAttributes["one.two"])
        XCTAssertNotNil(sanitized.attributes.userAttributes["one.two.three"])
        XCTAssertNotNil(sanitized.attributes.userAttributes["one.two.three.four"])
        XCTAssertNotNil(sanitized.attributes.userAttributes["one.two.three.four.five"])
        XCTAssertNotNil(sanitized.attributes.userAttributes["one.two.three.four.five.six"])
        XCTAssertNotNil(sanitized.attributes.userAttributes["one.two.three.four.five.six.seven"])
        XCTAssertNotNil(sanitized.attributes.userAttributes["one.two.three.four.five.six.seven.eight"])
        XCTAssertNotNil(sanitized.attributes.userAttributes["one.two.three.four.five.six.seven.eight.nine"])
        XCTAssertNotNil(sanitized.attributes.userAttributes["one.two.three.four.five.six.seven.eight.nine.ten"])
        XCTAssertNotNil(sanitized.attributes.userAttributes["one.two.three.four.five.six.seven.eight.nine.ten_eleven"])
        XCTAssertNotNil(sanitized.attributes.userAttributes["one.two.three.four.five.six.seven.eight.nine.ten_eleven_twelve"])
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
                    Tracer.Attributes.traceID: mockValue(),
                    Tracer.Attributes.spanID: mockValue(),
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
                    Tracer.Attributes.traceID: mockValue(),
                    Tracer.Attributes.spanID: mockValue(),
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
