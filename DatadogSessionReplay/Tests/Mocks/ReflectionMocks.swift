/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
@testable import DatadogSessionReplay
import TestUtilities
import SwiftUI
import CoreGraphics

private let bytesPerPixel = 4

private extension Int {
    static func mockImageDimension() -> Int {
        let min = 1, max = 10_000
        return Int.random(in: min...max)
    }
}

/// A mock implementation of `CGImage` for unit tests.
/// - Note: This mock creates a dummy RGBA image of configurable size.
/// - Warning: Ensure the width is within acceptable limits to avoid memory issues.
struct MockCGImage: RandomMockable {
    let cgImage: CGImage

    init(cgImage: CGImage) {
        self.cgImage = cgImage
    }

    static func mockRandom() -> MockCGImage {
        return MockCGImage(
            cgImage: mockWith()
        )
    }

    static func mockWith(
        width: Int = .mockImageDimension()
    ) -> CGImage {
        precondition(width > 0, "Width must be greater than 0")

        let totalBytes = width * width * bytesPerPixel

        // Allocate memory for pixel data
        guard let data = malloc(totalBytes) else {
            fatalError("Failed to allocate memory for pixel data")
        }

        // Free the allocated memory when the function exits
        defer { free(data) }

        // Fill the allocated memory with dummy data
        memset(data, 255, totalBytes)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: data,
            width: width,
            height: width,
            bitsPerComponent: 8,
            bytesPerRow: width * bytesPerPixel,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            fatalError("Failed to create CGContext for mock CGImage")
        }

        return context.makeImage()!
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension GraphicsImage: AnyMockable, RandomMockable {
    public static func mockAny() -> GraphicsImage {
        return GraphicsImage(
            contents: .cgImage(MockCGImage.mockRandom().cgImage),
            scale: 1.0,
            orientation: .up
        )
    }

    public static func mockRandom() -> GraphicsImage {
        return GraphicsImage(
            contents: .cgImage(MockCGImage.mockRandom().cgImage),
            scale: CGFloat.random(in: 0.5...3.0),
            orientation: .allCases.randomElement()!
        )
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension GraphicsImage.Contents: AnyMockable, RandomMockable {
    public static func mockAny() -> GraphicsImage.Contents {
        return .cgImage(MockCGImage.mockRandom().cgImage)
    }

    public static func mockRandom() -> GraphicsImage.Contents {
        return [.cgImage(MockCGImage.mockRandom().cgImage), .unknown].randomElement()!
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension SwiftUI.Image.Orientation: AnyMockable, RandomMockable {
    public static func mockAny() -> SwiftUI.Image.Orientation {
        return SwiftUI.Image.Orientation.up
    }

    public static func mockRandom() -> SwiftUI.Image.Orientation {
        return SwiftUI.Image.Orientation.allCases.randomElement()!
    }
}
#endif
