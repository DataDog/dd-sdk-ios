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
final class PathSessionReplayTests: XCTestCase {
    func testEmptyPath() {
        let path = Path()

        let svgString = path.dd.svgString

        XCTAssertEqual(svgString, "")
    }

    func testMoveToPoint() {
        var path = Path()
        path.move(to: CGPoint(x: 10.5, y: 20.25))

        let svgString = path.dd.svgString

        XCTAssertEqual(svgString, "M 10.500 20.250")
    }

    func testLineToPoint() {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 100, y: 50))

        let svgString = path.dd.svgString

        XCTAssertEqual(svgString, "M 0.000 0.000 L 100.000 50.000")
    }

    func testQuadCurveToPoint() {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addQuadCurve(to: CGPoint(x: 100, y: 100), control: CGPoint(x: 50, y: 0))

        let svgString = path.dd.svgString

        XCTAssertEqual(svgString, "M 0.000 0.000 Q 50.000 0.000 100.000 100.000")
    }

    func testCubicCurveToPoint() {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addCurve(to: CGPoint(x: 100, y: 100), control1: CGPoint(x: 25, y: 0), control2: CGPoint(x: 75, y: 100))

        let svgString = path.dd.svgString

        XCTAssertEqual(svgString, "M 0.000 0.000 C 25.000 0.000 75.000 100.000 100.000 100.000")
    }

    func testCloseSubpath() {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 100, y: 0))
        path.addLine(to: CGPoint(x: 100, y: 100))
        path.closeSubpath()

        let svgString = path.dd.svgString

        XCTAssertEqual(svgString, "M 0.000 0.000 L 100.000 0.000 L 100.000 100.000 Z")
    }

    func testMultipleSubpaths() {
        var path = Path()

        // First subpath - triangle
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 30, y: 0))
        path.addLine(to: CGPoint(x: 15, y: 25))
        path.closeSubpath()

        // Second subpath - circle approximation
        path.move(to: CGPoint(x: 50, y: 50))
        path.addQuadCurve(to: CGPoint(x: 100, y: 50), control: CGPoint(x: 75, y: 25))
        path.addQuadCurve(to: CGPoint(x: 50, y: 50), control: CGPoint(x: 75, y: 75))

        let svgString = path.dd.svgString

        let expected = "M 0.000 0.000 L 30.000 0.000 L 15.000 25.000 Z M 50.000 50.000 Q 75.000 25.000 100.000 50.000 Q 75.000 75.000 50.000 50.000"
        XCTAssertEqual(svgString, expected)
    }

    func testCoordinatePrecision() {
        var path = Path()
        path.move(to: CGPoint(x: 1.23456, y: 7.89123))
        path.addLine(to: CGPoint(x: 45.6789, y: 12.3456))

        let svgString = path.dd.svgString

        // Should round to 3 decimal places
        XCTAssertEqual(svgString, "M 1.235 7.891 L 45.679 12.346")
    }

    func testNegativeCoordinates() {
        var path = Path()
        path.move(to: CGPoint(x: -10.5, y: -20.75))
        path.addLine(to: CGPoint(x: -50, y: 30))

        let svgString = path.dd.svgString

        XCTAssertEqual(svgString, "M -10.500 -20.750 L -50.000 30.000")
    }
}
#endif
