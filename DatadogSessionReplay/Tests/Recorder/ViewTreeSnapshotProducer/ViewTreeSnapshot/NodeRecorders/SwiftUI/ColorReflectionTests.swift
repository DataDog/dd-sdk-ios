/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
import DatadogInternal
import CoreGraphics
import SwiftUI
@testable import DatadogSessionReplay

@available(iOS 13.0, tvOS 13.0, *)
class ColorReflectionTests: XCTestCase {
    func testColorResolvedReflection() throws {
        let color: SwiftUI.Color._Resolved = .mockRandom()
        let reflector = Reflector(subject: color, telemetry: NOPTelemetry())
        let reflectedColor = try SwiftUI.Color._Resolved(from: reflector)

        XCTAssertEqual(reflectedColor.linearRed, color.linearRed)
        XCTAssertEqual(reflectedColor.linearGreen, color.linearGreen)
        XCTAssertEqual(reflectedColor.linearBlue, color.linearBlue)
        XCTAssertEqual(reflectedColor.opacity, color.opacity)
    }

    func testResolvedPaintReflection() throws {
        let color: SwiftUI.Color._Resolved = .mockRandom()
        let paint = ResolvedPaint(paint: color)

        let reflector = Reflector(subject: paint, telemetry: NOPTelemetry())
        let reflectedPaint = try ResolvedPaint(from: reflector)

        XCTAssertNotNil(reflectedPaint.paint)
        XCTAssertEqual(reflectedPaint.paint?.linearRed, color.linearRed)
        XCTAssertEqual(reflectedPaint.paint?.linearGreen, color.linearGreen)
        XCTAssertEqual(reflectedPaint.paint?.linearBlue, color.linearBlue)
        XCTAssertEqual(reflectedPaint.paint?.opacity, color.opacity)
    }

    func testResolvedPaintReflection_withNilPaint() throws {
        let resolvedPaint = ResolvedPaint(paint: nil)

        let reflector = Reflector(subject: resolvedPaint, telemetry: NOPTelemetry())
        let reflectedPaint = try ResolvedPaint(from: reflector)

        XCTAssertNil(reflectedPaint.paint)
    }
}
#endif
