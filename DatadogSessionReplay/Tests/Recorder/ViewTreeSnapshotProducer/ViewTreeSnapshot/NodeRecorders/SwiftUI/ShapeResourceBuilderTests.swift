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
final class ShapeResourceBuilderTests: XCTestCase {
    private enum Fixtures {
        static let path = SwiftUI.Path {
            $0.addRect(.init(x: 0, y: 0, width: 50, height: 50))
        }
        static let otherPath = SwiftUI.Path {
            $0.move(to: .zero)
            $0.addLine(to: CGPoint(x: 50, y: 50))
        }
        static let size = CGSize(width: 50, height: 50)
    }

    func testSVGString() {
        // Given
        let builder = ShapeResourceBuilder()

        // When
        let resource = builder.shapeResource(
            for: Fixtures.path,
            color: .mockAny(),
            fillStyle: .init(),
            size: Fixtures.size
        )

        // Then
        XCTAssertEqual(
            resource.svgString,
            """
            <svg width=\"50.000\" height=\"50.000\" xmlns=\"http://www.w3.org/2000/svg\">
              <path d=\"M 0.000 0.000 L 50.000 0.000 L 50.000 50.000 L 0.000 50.000 Z\" \
            fill=\"#00000000\" fill-rule=\"nonzero\"/>
            </svg>
            """
        )
    }

    func testSVGStringEvenOddFillRule() {
        // Given
        let builder = ShapeResourceBuilder()

        // When
        let resource = builder.shapeResource(
            for: Fixtures.otherPath,
            color: .mockAny(),
            fillStyle: .init(eoFill: true),
            size: Fixtures.size
        )

        // Then
        XCTAssertEqual(
            resource.svgString,
            """
            <svg width="50.000" height="50.000" xmlns="http://www.w3.org/2000/svg">
              <path d="M 0.000 0.000 L 50.000 50.000" fill="#00000000" fill-rule="evenodd"/>
            </svg>
            """
        )
    }

    func testCacheHitReturnsCachedResource() {
        // Given
        let builder = ShapeResourceBuilder()

        // When
        let firstResource = builder.shapeResource(
            for: Fixtures.path,
            color: .mockAny(),
            fillStyle: .init(),
            size: Fixtures.size
        )

        // Then
        let secondResource = builder.shapeResource(
            for: Fixtures.path,
            color: .mockAny(),
            fillStyle: .init(),
            size: Fixtures.size
        )

        XCTAssertTrue(firstResource === secondResource)
    }

    func testCacheMissCreatesNewResource() {
        // Given
        let builder = ShapeResourceBuilder()

        // When
        let firstResource = builder.shapeResource(
            for: Fixtures.path,
            color: .mockAny(),
            fillStyle: .init(),
            size: Fixtures.size
        )

        // Then
        let secondResource = builder.shapeResource(
            for: Fixtures.otherPath,
            color: .mockAny(),
            fillStyle: .init(),
            size: Fixtures.size
        )

        XCTAssertFalse(firstResource === secondResource)
    }

    func testIdentifierStability() {
        // Given
        let svgString = """
            <svg width="50.000" height="50.000" xmlns="http://www.w3.org/2000/svg">
              <path d="M 0.000 0.000 L 50.000 50.000" fill="#00000000" fill-rule="evenodd"/>
            </svg>
            """

        // When
        let firstResource = ShapeResource(svgString: svgString)
        let secondResource = ShapeResource(svgString: svgString)

        // Then
        XCTAssertEqual(firstResource.calculateIdentifier(), "33102ea8ca2ccf8c37ba97cdb3391587")
        XCTAssertEqual(firstResource.calculateIdentifier(), secondResource.calculateIdentifier())
    }
}

#endif
