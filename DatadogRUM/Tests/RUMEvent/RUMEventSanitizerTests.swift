/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

class RUMEventSanitizerTests: XCTestCase {
    private let viewEvent: RUMViewEvent = .mockRandom()
    private let resourceEvent: RUMResourceEvent = .mockRandom()
    private let actionEvent: RUMActionEvent = .mockAny()
    private let errorEvent: RUMErrorEvent = .mockRandom()
    private let longTaskEvent: RUMLongTaskEvent = .mockRandom()
    private let vitalAppLaunchEvent: RUMVitalAppLaunchEvent = .mockRandom()
    private let vitalOperationStepEvent: RUMVitalOperationStepEvent = .mockRandom()

    func testWhenAttributeNameExceeds10NestedLevels_itIsEscapedByUnderscore() {
        var event = viewEvent
        event.context = RUMEventAttributes(contextInfo: [
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
        ])

        event.usr = RUMUser(usrInfo: [
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
        ])

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
        test(event: vitalAppLaunchEvent)
        test(event: vitalOperationStepEvent)
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
        test(event: vitalAppLaunchEvent)
        test(event: vitalOperationStepEvent)
    }

    func testWhenTotalSizeOfAttributesExceedsLimit_itPreservesValidAttributesByPriority() throws {
        // Four accepted attributes total 960 KiB, leaving enough room for the event envelope.
        let value = String(repeating: "a", count: 240 * 1_024)
        var event = viewEvent
        event.usr = RUMUser(
            usrInfo: [
                "user-1": value,
                "user-2": value,
            ]
        )
        event.account = RUMAccount(
            id: "account-id",
            accountInfo: [
                "account-1": value,
                "account-2": value,
            ]
        )
        event.context = RUMEventAttributes(
            contextInfo: [
                "context-1": value,
                "context-2": value,
            ]
        )

        // When
        let sanitized = RUMEventSanitizer().sanitize(event: event)

        // Then
        XCTAssertEqual(sanitized.usr?.usrInfo.count, 2)
        XCTAssertEqual(sanitized.account?.accountInfo.count, 2)
        XCTAssertTrue(sanitized.context?.contextInfo.isEmpty == true)
        XCTAssertLessThan(try JSONEncoder.dd.default().encode(sanitized).count, 1_024 * 1_024)
    }

    func testWhenInspectableNestedAttributeExceedsSizeLimit_itDropsOnlyThatAttributeAndLogsOneWarning() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let largeAttribute = [
            "values": [String(repeating: "a", count: RUMEventSanitizer.maxTotalAttributeBytes)]
        ]
        var event = viewEvent
        event.usr = RUMUser(usrInfo: [:])
        event.account = RUMAccount(id: "account-id", accountInfo: [:])
        event.context = RUMEventAttributes(
            contextInfo: [
                "small": "value",
                "large": largeAttribute,
            ]
        )

        // When
        let sanitized = RUMEventSanitizer().sanitize(event: event)

        // Then
        XCTAssertNotNil(sanitized.context?.contextInfo["small"])
        XCTAssertNil(sanitized.context?.contextInfo["large"])
        XCTAssertEqual(dd.logger.warnMessages.count, 1)
        XCTAssertEqual(
            dd.logger.warnLog?.message,
            """
            Size of RUM Event attributes exceeds the limit of \(RUMEventSanitizer.maxTotalAttributeBytes) bytes.
            1 attribute(s) will be ignored.
            """
        )
    }

    func testWhenAnyCodableContainsOversizedNativeValue_itDropsTheAttribute() {
        var event = viewEvent
        event.usr = RUMUser(usrInfo: [:])
        event.account = RUMAccount(id: "account-id", accountInfo: [:])
        event.context = RUMEventAttributes(
            contextInfo: [
                "small": "value",
                "large": AnyCodable([
                    "value": String(
                        repeating: "a",
                        count: RUMEventSanitizer.maxTotalAttributeBytes
                    )
                ]),
            ]
        )

        // When
        let sanitized = RUMEventSanitizer().sanitize(event: event)

        // Then
        XCTAssertNotNil(sanitized.context?.contextInfo["small"])
        XCTAssertNil(sanitized.context?.contextInfo["large"])
    }

    func testWhenNativeCollectionsContainUnsupportedFoundationValues_itDropsTheAttributes() {
        var event = viewEvent
        event.context = RUMEventAttributes(
            contextInfo: [
                "small": "value",
                "date": AnyEncodable([Date()] as [Any?]),
                "data": AnyEncodable([Data([0x00, 0xff, 0x42])] as [Any?]),
                "url": AnyEncodable([URL(string: "https://example.com")!] as [Any?]),
            ]
        )

        // When
        let sanitized = RUMEventSanitizer().sanitize(event: event)

        // Then
        XCTAssertNotNil(sanitized.context?.contextInfo["small"])
        XCTAssertNil(sanitized.context?.contextInfo["date"])
        XCTAssertNil(sanitized.context?.contextInfo["data"])
        XCTAssertNil(sanitized.context?.contextInfo["url"])
    }

    func testWhenNativeCollectionContainsUnknownEncodable_itDropsWithoutEncoding() {
        final class EncodingSpy: Encodable {
            private(set) var numberOfCalls = 0

            func encode(to encoder: Encoder) throws {
                numberOfCalls += 1
                var container = encoder.singleValueContainer()
                try container.encode("value")
            }
        }

        let value = EncodingSpy()
        let collection: [Any?] = [value]
        var event = viewEvent
        event.context = RUMEventAttributes(
            contextInfo: [
                "small": "value",
                "unknown": AnyEncodable(collection),
            ]
        )

        // When
        let sanitized = RUMEventSanitizer().sanitize(event: event)

        // Then
        XCTAssertNotNil(sanitized.context?.contextInfo["small"])
        XCTAssertNil(sanitized.context?.contextInfo["unknown"])
        XCTAssertEqual(value.numberOfCalls, 0)
    }

    func testWhenAttributeIsMutableObjectiveCCollection_itPreservesAndEncodesTheAttribute() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let mutableArray = NSMutableArray(array: ["value"])
        let mutableDictionary = NSMutableDictionary(dictionary: ["key": "value"])
        var event = viewEvent
        event.context = RUMEventAttributes(
            contextInfo: [
                "small": "value",
                "mutable-array": AnyEncodable(mutableArray),
                "mutable-dictionary": AnyEncodable(mutableDictionary),
            ]
        )

        // When
        let sanitized = RUMEventSanitizer().sanitize(event: event)
        mutableArray.add("later-value")
        mutableDictionary["later-key"] = "later-value"
        let encoded = try JSONEncoder.dd.default().encode(sanitized)

        // Then
        XCTAssertNotNil(sanitized.context?.contextInfo["small"])
        XCTAssertNotNil(sanitized.context?.contextInfo["mutable-array"])
        XCTAssertNotNil(sanitized.context?.contextInfo["mutable-dictionary"])
        XCTAssertEqual(
            try contextAttribute(named: "mutable-array", in: encoded) as? NSArray,
            ["value"]
        )
        XCTAssertEqual(
            try contextAttribute(named: "mutable-dictionary", in: encoded) as? NSDictionary,
            ["key": "value"]
        )
        XCTAssertTrue(dd.logger.warnMessages.isEmpty)
    }

    func testWhenEscapedStringExceedsEncodedSizeLimit_itDropsTheAttribute() {
        var event = viewEvent
        event.context = RUMEventAttributes(
            contextInfo: [
                "small": "value",
                // Each quote occupies two bytes in encoded JSON.
                "large": String(
                    repeating: "\"",
                    count: RUMEventSanitizer.maxTotalAttributeBytes / 2
                ),
            ]
        )

        // When
        let sanitized = RUMEventSanitizer().sanitize(event: event)

        // Then
        XCTAssertNotNil(sanitized.context?.contextInfo["small"])
        XCTAssertNil(sanitized.context?.contextInfo["large"])
    }

    func testWhenAttributeIsCustomEncodable_itLeavesItUnverifiedAndEncodesCustomerCodeOnlyOnce() throws {
        final class MirrorCallSpy {
            var wasCalled = false
        }

        final class StatefulAttribute: Encodable, CustomReflectable {
            let mirrorCallSpy: MirrorCallSpy
            private(set) var numberOfCalls = 0
            private(set) var observedCodingPath: [String] = []

            init(mirrorCallSpy: MirrorCallSpy) {
                self.mirrorCallSpy = mirrorCallSpy
            }

            var customMirror: Mirror {
                mirrorCallSpy.wasCalled = true
                return Mirror(self, children: [:])
            }

            func encode(to encoder: Encoder) throws {
                numberOfCalls += 1
                observedCodingPath = encoder.codingPath.map { $0.stringValue }

                var container = encoder.singleValueContainer()
                if numberOfCalls == 1 {
                    try container.encode(
                        String(repeating: "a", count: RUMEventSanitizer.maxTotalAttributeBytes)
                    )
                } else {
                    try container.encode("second-value")
                }
            }
        }

        let mirrorCallSpy = MirrorCallSpy()
        let attribute = StatefulAttribute(mirrorCallSpy: mirrorCallSpy)
        var event = viewEvent
        event.usr = RUMUser(usrInfo: [:])
        event.account = RUMAccount(id: "account-id", accountInfo: [:])
        event.context = RUMEventAttributes(contextInfo: ["stateful": attribute])

        // When
        let sanitized = RUMEventSanitizer().sanitize(event: event)
        let encoded = try JSONEncoder.dd.default().encode(sanitized)

        // Then
        XCTAssertFalse(mirrorCallSpy.wasCalled)
        XCTAssertEqual(attribute.numberOfCalls, 1)
        XCTAssertEqual(attribute.observedCodingPath, ["context", "stateful"])
        XCTAssertEqual(
            (try contextAttribute(named: "stateful", in: encoded) as? String)?.utf8.count,
            RUMEventSanitizer.maxTotalAttributeBytes
        )
    }

    func testWhenAttributeIsCustomEncodable_itPreservesItsEncodedJSONValue() throws {
        struct NestedValue: Encodable {
            let name: String
            let values: [Int]
            let flags: [String: Bool]
            let data: Data
            let date: Date
            let url: URL
            let decimal: Decimal
        }

        let attribute = NestedValue(
            name: "value",
            values: [1, 2, 3],
            flags: ["enabled": true, "disabled": false],
            data: Data([0x00, 0xff, 0x42]),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            url: URL(string: "path", relativeTo: URL(string: "https://example.com/base/"))!,
            decimal: Decimal(string: "1234.5678")!
        )
        var event = viewEvent
        event.usr = RUMUser(usrInfo: [:])
        event.account = RUMAccount(id: "account-id", accountInfo: [:])
        event.context = RUMEventAttributes(contextInfo: ["nested": attribute])

        let original = try JSONEncoder.dd.default().encode(event)

        // When
        let sanitized = RUMEventSanitizer().sanitize(event: event)
        let encoded = try JSONEncoder.dd.default().encode(sanitized)

        // Then
        XCTAssertEqual(
            try contextAttribute(named: "nested", in: encoded) as? NSDictionary,
            try contextAttribute(named: "nested", in: original) as? NSDictionary
        )
    }

    // MARK: - Private

    private func mockValue() -> String {
        return .mockAny()
    }

    private func contextAttribute(named name: String, in data: Data) throws -> Any? {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let context = try XCTUnwrap(object["context"] as? [String: Any])
        return context[name]
    }
}
