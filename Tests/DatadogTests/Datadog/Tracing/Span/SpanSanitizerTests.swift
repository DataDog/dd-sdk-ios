/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class SpanSanitizerTests: XCTestCase {
    func testWhenAttributeNameExceeds10NestedLevels_itIsEscapedByUnderscore() {
        let span = Span.mockWith(
            userInfo: .mockWith(
                extraInfo: [
                    "extra-info-one": mockValue(),
                    "extra-info-one.two": mockValue(),
                    "extra-info-one.two.three": mockValue(),
                    "extra-info-one.two.three.four": mockValue(),
                    "extra-info-one.two.three.four.five": mockValue(),
                    "extra-info-one.two.three.four.five.six": mockValue(),
                    "extra-info-one.two.three.four.five.six.seven": mockValue(),
                    "extra-info-one.two.three.four.five.six.seven.eight": mockValue(),
                    "extra-info-one.two.three.four.five.six.seven.eight.nine": mockValue(),
                    "extra-info-one.two.three.four.five.six.seven.eight.nine.ten": mockValue(),
                    "extra-info-one.two.three.four.five.six.seven.eight.nine.ten.eleven": mockValue(),
                    "extra-info-one.two.three.four.five.six.seven.eight.nine.ten.eleven.twelve": mockValue(),
                ]
            ),
            tags: [
                "tag-one": mockValue(),
                "tag-one.two": mockValue(),
                "tag-one.two.three": mockValue(),
                "tag-one.two.three.four": mockValue(),
                "tag-one.two.three.four.five": mockValue(),
                "tag-one.two.three.four.five.six": mockValue(),
                "tag-one.two.three.four.five.six.seven": mockValue(),
                "tag-one.two.three.four.five.six.seven.eight": mockValue(),
                "tag-one.two.three.four.five.six.seven.eight.nine": mockValue(),
                "tag-one.two.three.four.five.six.seven.eight.nine.ten": mockValue(),
                "tag-one.two.three.four.five.six.seven.eight.nine.ten.eleven": mockValue(),
                "tag-one.two.three.four.five.six.seven.eight.nine.ten.eleven.twelve": mockValue(),
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
        XCTAssertNotNil(sanitized.userInfo.extraInfo["extra-info-one.two.three.four.five.six.seven.eight_nine_ten"])
        XCTAssertNotNil(sanitized.userInfo.extraInfo["extra-info-one.two.three.four.five.six.seven.eight_nine_ten_eleven"])
        XCTAssertNotNil(sanitized.userInfo.extraInfo["extra-info-one.two.three.four.five.six.seven.eight_nine_ten_eleven_twelve"])

        XCTAssertEqual(sanitized.tags.count, 12)
        XCTAssertNotNil(sanitized.tags["tag-one"])
        XCTAssertNotNil(sanitized.tags["tag-one.two"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four.five"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four.five.six"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four.five.six.seven"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four.five.six.seven.eight"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four.five.six.seven.eight_nine_ten"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four.five.six.seven.eight_nine_ten_eleven"])
        XCTAssertNotNil(sanitized.tags["tag-one.two.three.four.five.six.seven.eight_nine_ten_eleven_twelve"])
    }

    func testWhenNumberOfAttributesExceedsLimit_itDropsExtraOnes() {
        let halfTheLimit = Int(Double(AttributesSanitizer.Constraints.maxNumberOfAttributes) * 0.5)
        let twiceTheLimit = AttributesSanitizer.Constraints.maxNumberOfAttributes * 2

        let numberOfUserExtraAttributes: Int = .random(in: halfTheLimit...twiceTheLimit)
        let numberOfTags: Int = .random(in: halfTheLimit...twiceTheLimit)

        let mockUserExtraAttributes = (0..<numberOfUserExtraAttributes).map { index in
            ("extra-info-\(index)", mockValue())
        }
        let mockTags = (0..<numberOfTags).map { index in
            ("tag-\(index)", mockValue())
        }

        let span = Span.mockWith(
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

    // MARK: - Private

    private func mockValue() -> JSONStringEncodableValue {
        return JSONStringEncodableValue(String.mockAny(), encodedUsing: JSONEncoder())
    }
}
