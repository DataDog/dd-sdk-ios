/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import XCTest
import UIKit

@testable import TestUtilities
@testable import DatadogSessionReplay

@available(iOS 13.0, tvOS 13.0, *)
final class ImageRendererTests: XCTestCase {
    func testCacheHitReturnsCachedImage() {
        // Given
        let renderer = ImageRenderer()
        let imageRepresentable = MockImageRepresentable.mockAny()

        // When
        let firstImage = renderer.image(for: imageRepresentable)

        // Then
        let secondImage = renderer.image(for: imageRepresentable)

        XCTAssertNotNil(firstImage)
        XCTAssertTrue(firstImage === secondImage)
    }

    func testCacheMissCreatesNewImage() {
        // Given
        let renderer = ImageRenderer()
        let firstImageRepresentable = MockImageRepresentable.mockAny()
        let secondImageRepresentable = MockImageRepresentable.mockAny()

        // When
        let firstImage = renderer.image(for: firstImageRepresentable)
        let secondImage = renderer.image(for: secondImageRepresentable)

        // Then
        XCTAssertNotNil(firstImage)
        XCTAssertNotNil(secondImage)
        XCTAssertFalse(firstImage === secondImage)
    }

    func testSameContentProducesCacheHit() {
        // Given
        let renderer = ImageRenderer()
        let cgImage = MockCGImage.mockWith(width: 100)
        let firstImageRepresentable = MockImageRepresentable(cgImage: cgImage)
        let secondImageRepresentable = MockImageRepresentable(cgImage: cgImage)

        // When
        let firstImage = renderer.image(for: firstImageRepresentable)
        let secondImage = renderer.image(for: secondImageRepresentable)

        // Then
        XCTAssertNotNil(firstImage)
        XCTAssertTrue(firstImage === secondImage)
    }

    func testImageGenerationWithFailingImageRepresentableReturnsNil() {
        // Given
        let renderer = ImageRenderer()
        let failingImageRepresentable = MockImageRepresentable()

        // When
        let image = renderer.image(for: failingImageRepresentable)

        // Then
        XCTAssertNil(image)
    }
}

#endif
