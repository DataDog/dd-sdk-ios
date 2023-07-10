/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogTrace

class SpanSanitizerTests: XCTestCase {
    func testWhenAttributeNameExceeds10NestedLevels_itIsEscapedByUnderscore() {
        let span = SpanEvent.mockWith(
            userInfo: .mockWith(
                extraInfo: [
                    "extra-info-one": .mockAny(),
                    "extra-info-one.two": .mockAny(),
                    "extra-info-one.two.three": .mockAny(),
                    "extra-info-one.two.three.four": .mockAny(),
                    "extra-info-one.two.three.four.five": .mockAny(),
                    "extra-info-one.two.three.four.five.six": .mockAny(),
                    "extra-info-one.two.three.four.five.six.seven": .mockAny(),
                    "extra-info-one.two.three.four.five.six.seven.eight": .mockAny(),
                    "extra-info-one.two.three.four.five.six.seven.eight.nine": .mockAny(),
                    "extra-info-one.two.three.four.five.six.seven.eight.nine.ten": .mockAny(),
                    "extra-info-one.two.three.four.five.six.seven.eight.nine.ten.eleven": .mockAny(),
                    "extra-info-one.two.three.four.five.six.seven.eight.nine.ten.eleven.twelve": .mockAny(),
                ]
            ),
            tags: [
                "tag-one": .mockAny(),
                "tag-one.two": .mockAny(),
                "tag-one.two.three": .mockAny(),
                "tag-one.two.three.four": .mockAny(),
                "tag-one.two.three.four.five": .mockAny(),
                "tag-one.two.three.four.five.six": .mockAny(),
                "tag-one.two.three.four.five.six.seven": .mockAny(),
                "tag-one.two.three.four.five.six.seven.eight": .mockAny(),
                "tag-one.two.three.four.five.six.seven.eight.nine": .mockAny(),
                "tag-one.two.three.four.five.six.seven.eight.nine.ten": .mockAny(),
                "tag-one.two.three.four.five.six.seven.eight.nine.ten.eleven": .mockAny(),
                "tag-one.two.three.four.five.six.seven.eight.nine.ten.eleven.twelve": .mockAny(),
            ]
        )

        // When
        let sanitized = SpanSanitizer().sanitize(span: span)

        // Then
        XCTAssertEqual(sanitized.userInfo.extraInfo.count, 12)
        XCTAssertNotNil(sanitized.userInfo.extraInfo["extra-info-one"])
        XCTAssertNotNil(sanitized.userInfo.extraInfo["extra-info-one.two"])
        XCTAssertNotNil(sanitized.userInfo.extraInfo["extra-info-one.two.three"])
        XCTAssertNotNil(sanitized.userInfo.extraInfo["extra-info-one.two.three.four"])
        XCTAssertNotNil(sanitized.userInfo.extraInfo["extra-info-one.two.three.four.five"])
        XCTAssertNotNil(sanitized.userInfo.extraInfo["extra-info-one.two.three.four.five.six"])
        XCTAssertNotNil(sanitized.userInfo.extraInfo["extra-info-one.two.three.four.five.six.seven"])
        XCTAssertNotNil(sanitized.userInfo.extraInfo["extra-info-one.two.three.four.five.six.seven.eight"])
        XCTAssertNotNil(sanitized.userInfo.extraInfo["extra-info-one.two.three.four.five.six.seven.eight.nine"])
        XCTAssertNotNil(sanitized.userInfo.extraInfo["extra-info-one.two.three.four.five.six.seven.eight.nine.ten"])
        XCTAssertNotNil(sanitized.userInfo.extraInfo["extra-info-one.two.three.four.five.six.seven.eight.nine.ten_eleven"])
        XCTAssertNotNil(sanitized.userInfo.extraInfo["extra-info-one.two.three.four.five.six.seven.eight.nine.ten_eleven_twelve"])

        XCTAssertEqual(sanitized.tags.count, 12)
        XCTAssertNotNil(sanitized.tags["tag-one"])
        XCTAssertNotNil(sanitized.tags["tag-one.two"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four.five"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four.five.six"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four.five.six.seven"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four.five.six.seven.eight"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four.five.six.seven.eight.nine"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four.five.six.seven.eight.nine.ten"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four.five.six.seven.eight.nine.ten_eleven"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four.five.six.seven.eight.nine.ten_eleven_twelve"])
    }

    func testWhenNumberOfAttributesExceedsLimit_itDropsExtraOnes() {
        let halfTheLimit = Int(Double(AttributesSanitizer.Constraints.maxNumberOfAttributes) * 0.5)
        let twiceTheLimit = AttributesSanitizer.Constraints.maxNumberOfAttributes * 2

        let numberOfUserExtraAttributes: Int = .random(in: halfTheLimit...twiceTheLimit)
        let numberOfTags: Int = .random(in: halfTheLimit...twiceTheLimit)

        let mockUserExtraAttributes = (0..<numberOfUserExtraAttributes).map { index in
            ("extra-info-\(index)", String.mockAny())
        }
        let mockTags = (0..<numberOfTags).map { index in
            ("tag-\(index)", String.mockAny())
        }

        let span = SpanEvent.mockWith(
            userInfo: .mockWith(
                extraInfo: Dictionary(uniqueKeysWithValues: mockUserExtraAttributes)
            ),
            tags: Dictionary(uniqueKeysWithValues: mockTags)
        )

        // When
        let sanitized = SpanSanitizer().sanitize(span: span)

        // Then
        XCTAssertEqual(
            sanitized.userInfo.extraInfo.count + sanitized.tags.count,
            AttributesSanitizer.Constraints.maxNumberOfAttributes
        )
        XCTAssertTrue(
            sanitized.userInfo.extraInfo.count >= sanitized.tags.count,
            "If number of attributes needs to be limited, `tags` are removed prior to `extraInfo` attributes."
        )
    }
}
