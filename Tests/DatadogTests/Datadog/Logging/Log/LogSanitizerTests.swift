/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class LogSanitizerTests: XCTestCase {
    // MARK: - Attributes sanitization

    func testWhenAttributeUsesReservedName_itIsIgnored() {
        let log = Log.mockWith(
            attributes: [
                // reserved attributes:
                "host": .mockAny(),
                "message": .mockAny(),
                "status": .mockAny(),
                "service": .mockAny(),
                "source": .mockAny(),
                "error.message": .mockAny(),
                "error.stack": .mockAny(),
                "ddtags": .mockAny(),

                // valid attributes:
                "attribute1": .mockAny(),
                "attribute2": .mockAny(),
                "date": .mockAny(),
            ]
        )

        let sanitized = LogSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.attributes?.count, 3)
        XCTAssertNotNil(sanitized.attributes?["attribute1"])
        XCTAssertNotNil(sanitized.attributes?["attribute2"])
        XCTAssertNotNil(sanitized.attributes?["date"])
    }

    func testWhenAttributeNameExceeds10NestedLevels_itIsEscapedByUnderscore() {
        let log = Log.mockWith(
            attributes: [
                "one": .mockAny(),
                "one.two": .mockAny(),
                "one.two.three": .mockAny(),
                "one.two.three.four": .mockAny(),
                "one.two.three.four.five": .mockAny(),
                "one.two.three.four.five.six": .mockAny(),
                "one.two.three.four.five.six.seven": .mockAny(),
                "one.two.three.four.five.six.seven.eight": .mockAny(),
                "one.two.three.four.five.six.seven.eight.nine": .mockAny(),
                "one.two.three.four.five.six.seven.eight.nine.ten": .mockAny(),
                "one.two.three.four.five.six.seven.eight.nine.ten.eleven": .mockAny(),
                "one.two.three.four.five.six.seven.eight.nine.ten.eleven.twelve": .mockAny(),
            ]
        )

        let sanitized = LogSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.attributes?.count, 12)
        XCTAssertNotNil(sanitized.attributes?["one"])
        XCTAssertNotNil(sanitized.attributes?["one.two"])
        XCTAssertNotNil(sanitized.attributes?["one.two.three"])
        XCTAssertNotNil(sanitized.attributes?["one.two.three.four"])
        XCTAssertNotNil(sanitized.attributes?["one.two.three.four.five"])
        XCTAssertNotNil(sanitized.attributes?["one.two.three.four.five.six"])
        XCTAssertNotNil(sanitized.attributes?["one.two.three.four.five.six.seven"])
        XCTAssertNotNil(sanitized.attributes?["one.two.three.four.five.six.seven.eight"])
        XCTAssertNotNil(sanitized.attributes?["one.two.three.four.five.six.seven.eight.nine.ten"])
        XCTAssertNotNil(sanitized.attributes?["one.two.three.four.five.six.seven.eight.nine.ten_eleven"])
        XCTAssertNotNil(sanitized.attributes?["one.two.three.four.five.six.seven.eight.nine.ten_eleven_twelve"])
    }

    func testWhenAttributeNameIsInvalid_itIsIgnored() {
        let log = Log.mockWith(
            attributes: [
                "valid-name": .mockAny(),
                "": .mockAny(), // invalid name
            ]
        )

        let sanitized = LogSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.attributes?.count, 1)
        XCTAssertNotNil(sanitized.attributes?["valid-name"])
    }

    func testWhenNumberOfAttributesExceedsLimit_itDropsExtraOnes() {
        let mockAttributes = (0...1_000).map { index in ("attribute-\(index)", EncodableValue.mockAny()) }
        let log = Log.mockWith(
            attributes: Dictionary(uniqueKeysWithValues: mockAttributes)
        )

        let sanitized = LogSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.attributes?.count, LogSanitizer.Constraints.maxNumberOfAttributes)
    }

    // MARK: - Tags sanitization

    func testWhenTagHasUpperCasedCharacters_itGetsLowerCased() {
        let log = Log.mockWith(
            tags: ["abcd", "Abcdef:ghi", "ABCDEF:GHIJK", "ABCDEFGHIJK"]
        )

        let sanitized = LogSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.tags, ["abcd", "abcdef:ghi", "abcdef:ghijk", "abcdefghijk"])
    }

    func testWhenTagStartsWithIllegalCharacter_itIsIgnored() {
        let log = Log.mockWith(
            tags: ["?invalid", "valid", "&invalid", ".abcdefghijk", ":abcd"]
        )

        let sanitized = LogSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.tags, ["valid"])
    }

    func testWhenTagContainsIllegalCharacter_itIsConvertedToUnderscore() {
        let log = Log.mockWith(
            tags: ["this&needs&underscore", "this*as*well", "this/doesnt", "tag with whitespaces"]
        )

        let sanitized = LogSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.tags, ["this_needs_underscore", "this_as_well", "this/doesnt", "tag_with_whitespaces"])
    }

    func testWhenTagContainsTrailingCommas_itItTruncatesThem() {
        let log = Log.mockWith(
            tags: ["with-one-comma:", "with-several-commas::::", "with-comma:in-the-middle"]
        )

        let sanitized = LogSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.tags, ["with-one-comma", "with-several-commas", "with-comma:in-the-middle"])
    }

    func testWhenTagExceedsLengthLimit_itIsTruncated() {
        let log = Log.mockWith(
            tags: [.mockRepeating(character: "a", times: 2 * LogSanitizer.Constraints.maxTagLength)]
        )

        let sanitized = LogSanitizer().sanitize(log: log)

        XCTAssertEqual(
            sanitized.tags,
            [.mockRepeating(character: "a", times: LogSanitizer.Constraints.maxTagLength)]
        )
    }

    func testWhenTagUsesReservedKey_itIsIgnored() {
        let log = Log.mockWith(
            tags: ["host:abc", "device:abc", "source:abc", "service:abc", "valid"]
        )

        let sanitized = LogSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.tags, ["valid"])
    }

    func testWhenNumberOfTagsExceedsLimit_itDropsExtraOnes() {
        let mockTags = (0...1_000).map { index in "tag\(index)" }
        let log = Log.mockWith(
            tags: mockTags
        )

        let sanitized = LogSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.tags?.count, LogSanitizer.Constraints.maxNumberOfTags)
    }
}
