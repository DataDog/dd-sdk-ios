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
        let smallImage: CGImage = MockCGImage.mockWith(width: 100)
        XCTAssertTrue(smallImage.isLikelyBundled(scale: 1.0))

        let largeImage: CGImage = MockCGImage.mockWith(width: 150)
        XCTAssertFalse(largeImage.isLikelyBundled(scale: 1.0))
    }
}
#endif
