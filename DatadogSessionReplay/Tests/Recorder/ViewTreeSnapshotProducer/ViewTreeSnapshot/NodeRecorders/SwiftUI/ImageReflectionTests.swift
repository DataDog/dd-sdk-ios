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
class ImageReflectionTests: XCTestCase {
    func testGraphicsImageReflection() {
        let contents: GraphicsImage.Contents = .mockAny()
        let scale: CGFloat = [1, 2, 3].randomElement()!
        let orientation: SwiftUI.Image.Orientation = .mockAny()
        let graphicsImage = GraphicsImage(
            contents: contents,
            scale: scale,
            orientation: orientation
        )
        XCTAssertNotNil(graphicsImage)
        XCTAssertEqual(graphicsImage.contents, contents)
        XCTAssertEqual(graphicsImage.scale, scale)
        XCTAssertEqual(graphicsImage.orientation, orientation)
    }

    func testGraphicsImageContentsReflectionWithCGImage() {
        let cgImage: CGImage = MockCGImage.mockWith(width: 20)
        let contents: GraphicsImage.Contents = .cgImage(cgImage)
        XCTAssertEqual(contents, .cgImage(cgImage))
    }

    func testGraphicsImageContentsReflectionWithUnknown() {
        let contents: GraphicsImage.Contents = .unknown
        XCTAssertEqual(contents, .unknown)
    }

    func testEnumCaseForCGImageGraphicsImageContents() {
        let cgImage: CGImage = MockCGImage.mockWith(width: 20)
        let contents: GraphicsImage.Contents = .cgImage(cgImage)

        switch contents {
        case .cgImage:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected .cgImage, got \(String(describing: contents))")
        }
    }

    func testReflectionParsingForGraphicsImage() {
        let graphicsImage = GraphicsImage.mockAny()
        let mirror = ReflectionMirror(reflecting: graphicsImage)
        XCTAssertNotNil(mirror)
        XCTAssertEqual(mirror.displayStyle, .struct)
    }

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
}
#endif
