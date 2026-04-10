/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM

class RUMEventSanitizerTests: XCTestCase {
    private let viewEvent: RUMViewEvent = .mockRandom()
    private let resourceEvent: RUMResourceEvent = .mockRandom()
    private let actionEvent: RUMActionEvent = .mockAny()
    private let errorEvent: RUMErrorEvent = .mockRandom()
    private let longTaskEvent: RUMLongTaskEvent = .mockRandom()

    func testWhenAttributeNameExceeds20NestedLevels_itIsEscapedByUnderscore() {
        func test<Event>(event: Event) where Event: RUMSanitizableEvent {
            var event = event
            // RUM sanitizer uses prefixLevels=1, so effective depth = 1 + key dots.
            // 18 dots (19 segments) — total depth 19 < 20, must NOT be escaped
            let keyUnchanged = "a.b.c.d.e.f.g.h.i.j.k.l.m.n.o.p.q.r.s"
            // 19 dots (20 segments) — total depth 20 >= 20, 19th dot must be escaped
            let keyToEscape = "a.b.c.d.e.f.g.h.i.j.k.l.m.n.o.p.q.r.s.t"
            let expectedKeyEscaped = "a.b.c.d.e.f.g.h.i.j.k.l.m.n.o.p.q.r.s_t"

            event.context?.contextInfo = [
                keyUnchanged: mockValue(),
                keyToEscape: mockValue(),
            ]
            event.usr?.usrInfo = [
                keyUnchanged: mockValue(),
                keyToEscape: mockValue(),
            ]

            // When
            let sanitized = RUMEventSanitizer().sanitize(event: event)

            // Then
            XCTAssertEqual(sanitized.context?.contextInfo.count, 2)
            XCTAssertNotNil(sanitized.context?.contextInfo[keyUnchanged], "18-dot key must be unchanged")
            XCTAssertNotNil(sanitized.context?.contextInfo[expectedKeyEscaped], "19th dot must be escaped to _")

            XCTAssertEqual(sanitized.usr?.usrInfo.count, 2)
            XCTAssertNotNil(sanitized.usr?.usrInfo[keyUnchanged], "18-dot key must be unchanged")
            XCTAssertNotNil(sanitized.usr?.usrInfo[expectedKeyEscaped], "19th dot must be escaped to _")
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
