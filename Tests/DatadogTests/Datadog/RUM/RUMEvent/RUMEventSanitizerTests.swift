/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMEventSanitizerTests: XCTestCase {
    private let viewEvent: RUMViewEvent = .mockRandom()
    private let resourceEvent: RUMResourceEvent = .mockRandom()
    private let actionEvent: RUMActionEvent = .mockRandom()
    private let errorEvent: RUMErrorEvent = .mockRandom()

    func testWhenAttributeNameExceeds10NestedLevels_itIsEscapedByUnderscore() {
        func test<DM: RUMDataModel>(model: DM) {
            let event = RUMEvent<DM>(
                model: model,
                attributes: [
                    "attribute-one": mockValue(),
                    "attribute-one.two": mockValue(),
                    "attribute-one.two.three": mockValue(),
                    "attribute-one.two.three.four": mockValue(),
                    "attribute-one.two.three.four.five": mockValue(),
                    "attribute-one.two.three.four.five.six": mockValue(),
                    "attribute-one.two.three.four.five.six.seven": mockValue(),
                    "attribute-one.two.three.four.five.six.seven.eight": mockValue(),
                    "attribute-one.two.three.four.five.six.seven.eight.nine": mockValue(),
                    "attribute-one.two.three.four.five.six.seven.eight.nine.ten": mockValue(),
                    "attribute-one.two.three.four.five.six.seven.eight.nine.ten.eleven": mockValue(),
                    "attribute-one.two.three.four.five.six.seven.eight.nine.ten.eleven.twelve": mockValue(),
                ],
                userInfoAttributes: [
                    "user-info-one": mockValue(),
                    "user-info-one.two": mockValue(),
                    "user-info-one.two.three": mockValue(),
                    "user-info-one.two.three.four": mockValue(),
                    "user-info-one.two.three.four.five": mockValue(),
                    "user-info-one.two.three.four.five.six": mockValue(),
                    "user-info-one.two.three.four.five.six.seven": mockValue(),
                    "user-info-one.two.three.four.five.six.seven.eight": mockValue(),
                    "user-info-one.two.three.four.five.six.seven.eight.nine": mockValue(),
                    "user-info-one.two.three.four.five.six.seven.eight.nine.ten": mockValue(),
                    "user-info-one.two.three.four.five.six.seven.eight.nine.ten.eleven": mockValue(),
                    "user-info-one.two.three.four.five.six.seven.eight.nine.ten.eleven.twelve": mockValue(),
                ],
                customViewTimings: [
                    "timing-one": .mockRandom(),
                    "timing-one.two": .mockRandom(),
                    "timing-one.two.three": .mockRandom(),
                    "timing-one.two.three.four": .mockRandom(),
                    "timing-one.two.three.four.five": .mockRandom(),
                    "timing-one.two.three.four.five.six": .mockRandom(),
                    "timing-one.two.three.four.five.six.seven": .mockRandom(),
                    "timing-one.two.three.four.five.six.seven.eight": .mockRandom(),
                    "timing-one.two.three.four.five.six.seven.eight.nine": .mockRandom(),
                    "timing-one.two.three.four.five.six.seven.eight.nine.ten": .mockRandom(),
                    "timing-one.two.three.four.five.six.seven.eight.nine.ten.eleven": .mockRandom(),
                    "timing-one.two.three.four.five.six.seven.eight.nine.ten.eleven.twelve": .mockRandom(),
                ]
            )

            // When
            let sanitized = RUMEventSanitizer().sanitize(event: event)

            // Then
            XCTAssertEqual(sanitized.attributes.count, 12)
            XCTAssertNotNil(sanitized.attributes["attribute-one"])
            XCTAssertNotNil(sanitized.attributes["attribute-one.two"])
            XCTAssertNotNil(sanitized.attributes["attribute-one.two.three"])
            XCTAssertNotNil(sanitized.attributes["attribute-one.two.three.four"])
            XCTAssertNotNil(sanitized.attributes["attribute-one.two.three.four.five"])
            XCTAssertNotNil(sanitized.attributes["attribute-one.two.three.four.five.six"])
            XCTAssertNotNil(sanitized.attributes["attribute-one.two.three.four.five.six.seven"])
            XCTAssertNotNil(sanitized.attributes["attribute-one.two.three.four.five.six.seven.eight"])
            XCTAssertNotNil(sanitized.attributes["attribute-one.two.three.four.five.six.seven.eight_nine_ten"])
            XCTAssertNotNil(sanitized.attributes["attribute-one.two.three.four.five.six.seven.eight_nine_ten_eleven"])
            XCTAssertNotNil(sanitized.attributes["attribute-one.two.three.four.five.six.seven.eight_nine_ten_eleven_twelve"])

            XCTAssertEqual(sanitized.userInfoAttributes.count, 12)
            XCTAssertNotNil(sanitized.userInfoAttributes["user-info-one"])
            XCTAssertNotNil(sanitized.userInfoAttributes["user-info-one.two"])
            XCTAssertNotNil(sanitized.userInfoAttributes["user-info-one.two.three"])
            XCTAssertNotNil(sanitized.userInfoAttributes["user-info-one.two.three.four"])
            XCTAssertNotNil(sanitized.userInfoAttributes["user-info-one.two.three.four.five"])
            XCTAssertNotNil(sanitized.userInfoAttributes["user-info-one.two.three.four.five.six"])
            XCTAssertNotNil(sanitized.userInfoAttributes["user-info-one.two.three.four.five.six.seven"])
            XCTAssertNotNil(sanitized.userInfoAttributes["user-info-one.two.three.four.five.six.seven.eight"])
            XCTAssertNotNil(sanitized.userInfoAttributes["user-info-one.two.three.four.five.six.seven.eight_nine_ten"])
            XCTAssertNotNil(sanitized.userInfoAttributes["user-info-one.two.three.four.five.six.seven.eight_nine_ten_eleven"])
            XCTAssertNotNil(sanitized.userInfoAttributes["user-info-one.two.three.four.five.six.seven.eight_nine_ten_eleven_twelve"])

            XCTAssertEqual(sanitized.customViewTimings?.count, 12)
            XCTAssertNotNil(sanitized.customViewTimings?["timing-one"])
            XCTAssertNotNil(sanitized.customViewTimings?["timing-one.two"])
            XCTAssertNotNil(sanitized.customViewTimings?["timing-one.two.three"])
            XCTAssertNotNil(sanitized.customViewTimings?["timing-one.two.three.four"])
            XCTAssertNotNil(sanitized.customViewTimings?["timing-one.two.three.four.five"])
            XCTAssertNotNil(sanitized.customViewTimings?["timing-one.two.three.four.five.six"])
            XCTAssertNotNil(sanitized.customViewTimings?["timing-one.two.three.four.five.six.seven"])
            XCTAssertNotNil(sanitized.customViewTimings?["timing-one.two.three.four.five.six.seven.eight"])
            XCTAssertNotNil(sanitized.customViewTimings?["timing-one.two.three.four.five.six.seven.eight_nine_ten"])
            XCTAssertNotNil(sanitized.customViewTimings?["timing-one.two.three.four.five.six.seven.eight_nine_ten_eleven"])
            XCTAssertNotNil(sanitized.customViewTimings?["timing-one.two.three.four.five.six.seven.eight_nine_ten_eleven_twelve"])
        }

        test(model: viewEvent)
        test(model: resourceEvent)
        test(model: actionEvent)
        test(model: errorEvent)
    }

    func testWhenNumberOfAttributesExceedsLimit_itDropsExtraOnes() {
        func test<DM: RUMDataModel>(model: DM) {
            let oneThirdOfTheLimit = Int(Double(AttributesSanitizer.Constraints.maxNumberOfAttributes) * 0.34)
            let tripleTheLimit = AttributesSanitizer.Constraints.maxNumberOfAttributes * 3

            let numberOfAttributes: Int = .random(in: oneThirdOfTheLimit...tripleTheLimit)
            let numberOfUserInfoAttributes: Int = .random(in: oneThirdOfTheLimit...tripleTheLimit)
            let numberOfTimings: Int = .random(in: oneThirdOfTheLimit...tripleTheLimit)

            let mockAttributes = (0..<numberOfAttributes).map { index in
                ("attribute-\(index)", mockValue())
            }
            let mockUserInfoAttributes = (0..<numberOfUserInfoAttributes).map { index in
                ("user-info-\(index)", mockValue())
            }
            let mockTimings = (0..<numberOfTimings).map { index in
                ("timing-\(index)", Int64.mockAny())
            }

            let event = RUMEvent<DM>(
                model: model,
                attributes: Dictionary(uniqueKeysWithValues: mockAttributes),
                userInfoAttributes: Dictionary(uniqueKeysWithValues: mockUserInfoAttributes),
                customViewTimings: Dictionary(uniqueKeysWithValues: mockTimings)
            )

            // When
            let sanitized = RUMEventSanitizer().sanitize(event: event)

            // Then
            var remaining = AttributesSanitizer.Constraints.maxNumberOfAttributes
            let expectedSanitizedCustomTimings = min(sanitized.customViewTimings!.count, remaining)
            remaining -= expectedSanitizedCustomTimings
            let expectedSanitizedUserInfo = min(sanitized.userInfoAttributes.count, remaining)
            remaining -= expectedSanitizedUserInfo
            let expectedSanitizedAttrs = min(sanitized.attributes.count, remaining)
            remaining -= expectedSanitizedAttrs

            XCTAssertGreaterThanOrEqual(remaining, 0)
            XCTAssertEqual(sanitized.customViewTimings!.count, expectedSanitizedCustomTimings, "If number of attributes needs to be limited, `customViewTimings` are removed last")
            XCTAssertEqual(sanitized.userInfoAttributes.count, expectedSanitizedUserInfo, "If number of attributes needs to be limited, `userInfoAttributes` are removed second")
            XCTAssertEqual(sanitized.attributes.count, expectedSanitizedAttrs, "If number of attributes needs to be limited, `attributes` are removed first.")
        }

        test(model: viewEvent)
        test(model: resourceEvent)
        test(model: actionEvent)
        test(model: errorEvent)
    }

    // MARK: - Private

    private func mockValue() -> String {
        return .mockAny()
    }
}
