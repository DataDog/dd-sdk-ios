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
            XCTAssertNotNil(sanitized.attributes["attribute-one.two.three.four.five.six.seven.eight.nine_ten"])
            XCTAssertNotNil(sanitized.attributes["attribute-one.two.three.four.five.six.seven.eight.nine_ten_eleven"])
            XCTAssertNotNil(sanitized.attributes["attribute-one.two.three.four.five.six.seven.eight.nine_ten_eleven_twelve"])

            XCTAssertEqual(sanitized.userInfoAttributes.count, 12)
            XCTAssertNotNil(sanitized.userInfoAttributes["user-info-one"])
            XCTAssertNotNil(sanitized.userInfoAttributes["user-info-one.two"])
            XCTAssertNotNil(sanitized.userInfoAttributes["user-info-one.two.three"])
            XCTAssertNotNil(sanitized.userInfoAttributes["user-info-one.two.three.four"])
            XCTAssertNotNil(sanitized.userInfoAttributes["user-info-one.two.three.four.five"])
            XCTAssertNotNil(sanitized.userInfoAttributes["user-info-one.two.three.four.five.six"])
            XCTAssertNotNil(sanitized.userInfoAttributes["user-info-one.two.three.four.five.six.seven"])
            XCTAssertNotNil(sanitized.userInfoAttributes["user-info-one.two.three.four.five.six.seven.eight"])
            XCTAssertNotNil(sanitized.userInfoAttributes["user-info-one.two.three.four.five.six.seven.eight.nine_ten"])
            XCTAssertNotNil(sanitized.userInfoAttributes["user-info-one.two.three.four.five.six.seven.eight.nine_ten_eleven"])
            XCTAssertNotNil(sanitized.userInfoAttributes["user-info-one.two.three.four.five.six.seven.eight.nine_ten_eleven_twelve"])
        }

        test(model: viewEvent)
        test(model: resourceEvent)
        test(model: actionEvent)
        test(model: errorEvent)
    }

    func testWhenNumberOfAttributesExceedsLimit_itDropsExtraOnes() {
        func test<DM: RUMDataModel>(model: DM) {
            let oneHalfOfTheLimit = Int(Double(AttributesSanitizer.Constraints.maxNumberOfAttributes) * 0.5)
            let twiceTheLimit = AttributesSanitizer.Constraints.maxNumberOfAttributes * 2

            let numberOfAttributes: Int = .random(in: oneHalfOfTheLimit...twiceTheLimit)
            let numberOfUserInfoAttributes: Int = .random(in: oneHalfOfTheLimit...twiceTheLimit)

            let mockAttributes = (0..<numberOfAttributes).map { index in
                ("attribute-\(index)", mockValue())
            }
            let mockUserInfoAttributes = (0..<numberOfUserInfoAttributes).map { index in
                ("user-info-\(index)", mockValue())
            }

            let event = RUMEvent<DM>(
                model: model,
                attributes: Dictionary(uniqueKeysWithValues: mockAttributes),
                userInfoAttributes: Dictionary(uniqueKeysWithValues: mockUserInfoAttributes)
            )

            // When
            let sanitized = RUMEventSanitizer().sanitize(event: event)

            // Then
            var remaining = AttributesSanitizer.Constraints.maxNumberOfAttributes
            let expectedSanitizedUserInfo = min(sanitized.userInfoAttributes.count, remaining)
            remaining -= expectedSanitizedUserInfo
            let expectedSanitizedAttrs = min(sanitized.attributes.count, remaining)
            remaining -= expectedSanitizedAttrs

            XCTAssertGreaterThanOrEqual(remaining, 0)
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
