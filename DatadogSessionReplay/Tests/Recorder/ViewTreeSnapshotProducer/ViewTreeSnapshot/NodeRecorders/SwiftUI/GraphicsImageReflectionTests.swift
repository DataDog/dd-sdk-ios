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
import TestUtilities
@testable import DatadogSessionReplay

@available(iOS 13.0, tvOS 13.0, *)
class GraphicsImageReflectionTests: XCTestCase {
    // MARK: Object Behavior tests
    func testGraphicsImageContentsEquality() {
        let cgImage1: CGImage = MockCGImage.mockWith(width: 20)
        let cgImage2: CGImage = MockCGImage.mockWith(width: 20)

        // Check equality
        let contents1 = GraphicsImage.Contents.cgImage(cgImage1)
        let contents2 = GraphicsImage.Contents.cgImage(cgImage1)
        XCTAssertEqual(contents1, contents2, "GraphicsImage.Contents should be equal if cgImage is the same.")

        // Check inequality
        let contents3 = GraphicsImage.Contents.cgImage(cgImage2)
        XCTAssertNotEqual(contents1, contents3, "GraphicsImage.Contents should not be equal for different cgImages.")
    }

    func testCGImageBundlingHeuristic() {
        // Given
        let smallImageWidth: Int = 100
        let largeImageWidth: Int = 150

        // Then
        let scalex1: CGFloat = 1
        let smallImage1x: CGImage = MockCGImage.mockWith(width: smallImageWidth, scale: scalex1)
        XCTAssertTrue(smallImage1x.isLikelyBundled(scale: scalex1))
        let largeImage1x: CGImage = MockCGImage.mockWith(width: largeImageWidth, scale: scalex1)
        XCTAssertFalse(largeImage1x.isLikelyBundled(scale: scalex1))

        // Then
        let scale2x: CGFloat = 2
        let smallImage2x: CGImage = MockCGImage.mockWith(width: smallImageWidth, scale: scale2x)
        XCTAssertTrue(smallImage2x.isLikelyBundled(scale: scale2x))
        let largeImage2x: CGImage = MockCGImage.mockWith(width: largeImageWidth, scale: scale2x)
        XCTAssertFalse(largeImage2x.isLikelyBundled(scale: scale2x))

        // Then
        let scale3x: CGFloat = 3
        let smallImage3x: CGImage = MockCGImage.mockWith(width: smallImageWidth, scale: scale3x)
        XCTAssertTrue(smallImage3x.isLikelyBundled(scale: scale3x))
        let largeImage3x: CGImage = MockCGImage.mockWith(width: largeImageWidth, scale: scale3x)
        XCTAssertFalse(largeImage3x.isLikelyBundled(scale: scale3x))
    }

    // MARK: Reflection tests
    func testGraphicsImageReflection() throws {
        let cgImage: CGImage = MockCGImage.mockWith(width: 20)
        let graphicsImage = GraphicsImage(
            contents: .cgImage(cgImage),
            scale: 2.0,
            orientation: .up,
            maskColor: .mockRandom()
        )

        let reflector = Reflector(subject: graphicsImage, telemetry: NOPTelemetry())
        let reflectedImage = try GraphicsImage(from: reflector)

        XCTAssertEqual(reflectedImage.scale, graphicsImage.scale)
        XCTAssertEqual(reflectedImage.orientation, graphicsImage.orientation)
        XCTAssertEqual(reflectedImage.contents, graphicsImage.contents)
        XCTAssertEqual(reflectedImage.maskColor, graphicsImage.maskColor)
    }

    func testGraphicsImageContentsReflection_withCGImage() throws {
        let cgImage: CGImage = MockCGImage.mockWith(width: 20)
        let contents = GraphicsImage.Contents.cgImage(cgImage)

        let reflector = Reflector(subject: contents, telemetry: NOPTelemetry())
        let reflectedContents = try GraphicsImage.Contents(from: reflector)

        XCTAssertEqual(reflectedContents, contents)
    }

    func testGraphicsImageContentsReflection_withUnknown() throws {
        let contents = GraphicsImage.Contents.unknown

        let reflector = Reflector(subject: contents, telemetry: NOPTelemetry())
        let reflectedContents = try GraphicsImage.Contents(from: reflector)

        XCTAssertEqual(reflectedContents, contents)
    }
}
#endif
