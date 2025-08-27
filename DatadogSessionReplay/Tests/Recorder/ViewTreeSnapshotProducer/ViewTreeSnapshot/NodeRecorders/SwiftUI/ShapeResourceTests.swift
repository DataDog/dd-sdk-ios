/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import XCTest
import SwiftUI
@testable import DatadogSessionReplay

@available(iOS 13.0, tvOS 13.0, *)
final class ShapeResourceTests: XCTestCase {
    private enum Fixtures {
        static let shapeResource = ShapeResource(
            path: .init {
                $0.addRect(.init(x: 0, y: 0, width: 50, height: 50))
            },
            color: .mockAny(),
            fillStyle: .init(),
            size: .init(width: 50, height: 50)
        )
        static let shapeResourceWithEvenOddFillRule = ShapeResource(
            path: .init {
                $0.move(to: .zero)
                $0.addLine(to: CGPoint(x: 50, y: 50))
            },
            color: .mockAny(),
            fillStyle: .init(eoFill: true),
            size: .init(width: 50, height: 50)
        )
    }

    func testSVGString() {
        XCTAssertEqual(
            Fixtures.shapeResource.svgString,
            """
            <svg width=\"50.000\" height=\"50.000\" xmlns=\"http://www.w3.org/2000/svg\">
              <path d=\"M 0.000 0.000 L 50.000 0.000 L 50.000 50.000 L 0.000 50.000 Z\" \
            fill=\"#00000000\" fill-rule=\"nonzero\"/>
            </svg>
            """
        )
    }

    func testSVGStringEvenOddFillRule() {
        XCTAssertEqual(
            Fixtures.shapeResourceWithEvenOddFillRule.svgString,
            """
            <svg width="50.000" height="50.000" xmlns="http://www.w3.org/2000/svg">
              <path d="M 0.000 0.000 L 50.000 50.000" fill="#00000000" fill-rule="evenodd"/>
            </svg>
            """
        )
    }

    func testMimeType() {
        XCTAssertEqual(Fixtures.shapeResource.mimeType, "image/svg+xml")
    }

    func testCalculateIdentifier() {
        let identifier = Fixtures.shapeResource.calculateIdentifier()

        XCTAssertEqual(identifier.count, 32)
        XCTAssertTrue(identifier.allSatisfy { $0.isHexDigit })

        XCTAssertEqual(
            Fixtures.shapeResource.calculateIdentifier(),
            Fixtures.shapeResource.calculateIdentifier()
        )
        XCTAssertNotEqual(
            Fixtures.shapeResource.calculateIdentifier(),
            Fixtures.shapeResourceWithEvenOddFillRule.calculateIdentifier()
        )
    }

    func testCalculateData() {
        let data = Fixtures.shapeResource.calculateData()
        let svgString = String(data: data, encoding: .utf8)

        XCTAssertNotNil(svgString)
        XCTAssertEqual(svgString, Fixtures.shapeResource.svgString)
    }
}

extension Character {
    fileprivate var isHexDigit: Bool {
        return isASCII && (isNumber || ("a"..."f").contains(lowercased().first!))
    }
}

#endif
