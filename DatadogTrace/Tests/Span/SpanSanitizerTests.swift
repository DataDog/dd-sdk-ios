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
    func testWhenAttributeNameExceeds20NestedLevels_itIsEscapedByUnderscore() {
        // SpanSanitizer uses prefixLevels=0, so escape starts at dot 20.
        let keyUnchanged = "a.b.c.d.e.f.g.h.i.j.k.l.m.n.o.p.q.r.s.t"   // 19 dots — at limit
        let keyToEscape = "a.b.c.d.e.f.g.h.i.j.k.l.m.n.o.p.q.r.s.t.u"  // 20 dots — 20th dot escaped
        let expectedKeyEscaped = "a.b.c.d.e.f.g.h.i.j.k.l.m.n.o.p.q.r.s.t_u"

        let span = SpanEvent.mockWith(
            userInfo: .mockWith(
                extraInfo: [
                    keyUnchanged: .mockAny(),
                    keyToEscape: .mockAny(),
                ]
            ),
            tags: [
                keyUnchanged: .mockAny(),
                keyToEscape: .mockAny(),
            ]
        )

        // When
        let sanitized = SpanSanitizer().sanitize(span: span)

        // Then
        XCTAssertEqual(sanitized.userInfo.extraInfo.count, 2)
        XCTAssertNotNil(sanitized.userInfo.extraInfo[keyUnchanged], "19-dot key must be unchanged")
        XCTAssertNotNil(sanitized.userInfo.extraInfo[expectedKeyEscaped], "20th dot must be escaped to _")

        XCTAssertEqual(sanitized.tags.count, 2)
        XCTAssertNotNil(sanitized.tags[keyUnchanged], "19-dot key must be unchanged")
        XCTAssertNotNil(sanitized.tags[expectedKeyEscaped], "20th dot must be escaped to _")
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
