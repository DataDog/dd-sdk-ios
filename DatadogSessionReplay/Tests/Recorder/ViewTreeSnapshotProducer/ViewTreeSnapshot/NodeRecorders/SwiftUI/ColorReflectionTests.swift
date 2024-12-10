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
        let red: Float = .mockRandom(min: 0, max: 1)
        let green: Float = .mockRandom(min: 0, max: 1)
        let blue: Float = .mockRandom(min: 0, max: 1)
        let opacity: Float = .mockRandom(min: 0, max: 1)

        let mockColor = SwiftUI.Color._Resolved(
            linearRed: red,
            linearGreen: green,
            linearBlue: blue,
            opacity: opacity
        )
        let mirror = ReflectionMirror(reflecting: mockColor)

        let reflectedColor = try SwiftUI.Color._Resolved(mirror)

        XCTAssertEqual(reflectedColor.linearRed, red)
        XCTAssertEqual(reflectedColor.linearGreen, green)
        XCTAssertEqual(reflectedColor.linearBlue, blue)
        XCTAssertEqual(reflectedColor.opacity, opacity)
    }

    func testResolvedPaintReflection_withValidPaint() throws {
        let red: Float = .mockRandom(min: 0, max: 1)
        let green: Float = .mockRandom(min: 0, max: 1)
        let blue: Float = .mockRandom(min: 0, max: 1)
        let opacity: Float = .mockRandom(min: 0, max: 1)

        let mockColor = SwiftUI.Color._Resolved(
            linearRed: red,
            linearGreen: green,
            linearBlue: blue,
            opacity: opacity
        )
        let mockPaint = ResolvedPaint(paint: mockColor)
        let mirror = ReflectionMirror(reflecting: mockPaint)

        let resolvedPaint = try ResolvedPaint(mirror)
        XCTAssertNotNil(resolvedPaint.paint)
        XCTAssertEqual(resolvedPaint.paint?.linearRed, mockColor.linearRed)
        XCTAssertEqual(resolvedPaint.paint?.linearGreen, mockColor.linearGreen)
        XCTAssertEqual(resolvedPaint.paint?.linearBlue, mockColor.linearBlue)
        XCTAssertEqual(resolvedPaint.paint?.opacity, mockColor.opacity)
    }
}
#endif
