/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMEventSanitizerTests: XCTestCase {
    private let viewEvent: RUMViewEvent = .mockRandom()
    private let resourceEvent: RUMResourceEvent = .mockRandom()
    private let actionEvent: RUMActionEvent = .mockRandom()
    private let errorEvent: RUMErrorEvent = .mockRandom()
    private let longTaskEvent: RUMLongTaskEvent = .mockRandom()

    func testWhenAttributeNameExceeds10NestedLevels_itIsEscapedByUnderscore() {
        func test<Event>(event: Event) where Event: RUMSanitizableEvent {
            var event = event
            event.context?.contextInfo = [
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
            ]

            event.usr?.usrInfo = [
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

            // When
            let sanitized = RUMEventSanitizer().sanitize(event: event)

            // Then
            XCTAssertEqual(sanitized.context?.contextInfo.count, 12)
            XCTAssertNotNil(sanitized.context?.contextInfo["attribute-one"])
            XCTAssertNotNil(sanitized.context?.contextInfo["attribute-one.two"])
            XCTAssertNotNil(sanitized.context?.contextInfo["attribute-one.two.three"])
            XCTAssertNotNil(sanitized.context?.contextInfo["attribute-one.two.three.four"])
            XCTAssertNotNil(sanitized.context?.contextInfo["attribute-one.two.three.four.five"])
            XCTAssertNotNil(sanitized.context?.contextInfo["attribute-one.two.three.four.five.six"])
            XCTAssertNotNil(sanitized.context?.contextInfo["attribute-one.two.three.four.five.six.seven"])
            XCTAssertNotNil(sanitized.context?.contextInfo["attribute-one.two.three.four.five.six.seven.eight"])
            XCTAssertNotNil(sanitized.context?.contextInfo["attribute-one.two.three.four.five.six.seven.eight.nine_ten"])
            XCTAssertNotNil(sanitized.context?.contextInfo["attribute-one.two.three.four.five.six.seven.eight.nine_ten_eleven"])
            XCTAssertNotNil(sanitized.context?.contextInfo["attribute-one.two.three.four.five.six.seven.eight.nine_ten_eleven_twelve"])

            XCTAssertEqual(sanitized.usr?.usrInfo.count, 12)
            XCTAssertNotNil(sanitized.usr?.usrInfo["user-info-one"])
            XCTAssertNotNil(sanitized.usr?.usrInfo["user-info-one.two"])
            XCTAssertNotNil(sanitized.usr?.usrInfo["user-info-one.two.three"])
            XCTAssertNotNil(sanitized.usr?.usrInfo["user-info-one.two.three.four"])
            XCTAssertNotNil(sanitized.usr?.usrInfo["user-info-one.two.three.four.five"])
            XCTAssertNotNil(sanitized.usr?.usrInfo["user-info-one.two.three.four.five.six"])
            XCTAssertNotNil(sanitized.usr?.usrInfo["user-info-one.two.three.four.five.six.seven"])
            XCTAssertNotNil(sanitized.usr?.usrInfo["user-info-one.two.three.four.five.six.seven.eight"])
            XCTAssertNotNil(sanitized.usr?.usrInfo["user-info-one.two.three.four.five.six.seven.eight.nine_ten"])
            XCTAssertNotNil(sanitized.usr?.usrInfo["user-info-one.two.three.four.five.six.seven.eight.nine_ten_eleven"])
            XCTAssertNotNil(sanitized.usr?.usrInfo["user-info-one.two.three.four.five.six.seven.eight.nine_ten_eleven_twelve"])
        }

        test(event: viewEvent)
        test(event: resourceEvent)
        test(event: actionEvent)
        test(event: errorEvent)
        test(event: longTaskEvent)
    }

    func testWhenNumberOfAttributesExceedsLimit_itDropsExtraOnes() {
        func test<Event>(event: Event) where Event: RUMSanitizableEvent {
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

            var event = event
            event.context?.contextInfo = Dictionary(uniqueKeysWithValues: mockAttributes)
            event.usr?.usrInfo = Dictionary(uniqueKeysWithValues: mockUserInfoAttributes)

            // When
            let sanitized = RUMEventSanitizer().sanitize(event: event)

            // Then
            var remaining = AttributesSanitizer.Constraints.maxNumberOfAttributes
            let expectedSanitizedUserInfo = min(sanitized.usr!.usrInfo.count , remaining)
            remaining -= expectedSanitizedUserInfo
            let expectedSanitizedAttrs = min(sanitized.context!.contextInfo.count, remaining)
            remaining -= expectedSanitizedAttrs

            XCTAssertGreaterThanOrEqual(remaining, 0)
            XCTAssertEqual(sanitized.usr?.usrInfo.count, expectedSanitizedUserInfo, "If number of attributes needs to be limited, `usrInfo` are removed second")
            XCTAssertEqual(sanitized.context?.contextInfo.count, expectedSanitizedAttrs, "If number of attributes needs to be limited, `contextInfo` are removed first.")
        }

        test(event: viewEvent)
        test(event: resourceEvent)
        test(event: actionEvent)
        test(event: errorEvent)
        test(event: longTaskEvent)
    }

    // MARK: - Private

    private func mockValue() -> String {
        return .mockAny()
    }
}
