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

// MARK: Text
extension ResolvedStyledText.StringDrawing: AnyMockable, RandomMockable {
    public static func mockAny() -> ResolvedStyledText.StringDrawing {
        return ResolvedStyledText.StringDrawing(storage: NSAttributedString(string: .mockAny()))
    }

    public static func mockRandom() -> ResolvedStyledText.StringDrawing {
        return ResolvedStyledText.StringDrawing(storage: NSAttributedString(string: .mockRandom()))
    }
}

extension StyledTextContentView: AnyMockable, RandomMockable {
    public static func mockAny() -> StyledTextContentView {
        return StyledTextContentView(text: .mockAny())
    }

    public static func mockRandom() -> StyledTextContentView {
        return StyledTextContentView(text: .mockRandom())
    }
}

// MARK: Color
@available(iOS 13.0, tvOS 13.0, *)
extension SwiftUI.Color._Resolved: AnyMockable, RandomMockable {
    public static func mockAny() -> Color._Resolved {
        return SwiftUI.Color._Resolved(
            linearRed: .mockAny(),
            linearGreen: .mockAny(),
            linearBlue: .mockAny(),
            opacity: .mockAny()
        )
    }

    public static func mockRandom() -> SwiftUI.Color._Resolved {
        return SwiftUI.Color._Resolved(
            linearRed: .mockRandom(min: 0, max: 1),
            linearGreen: .mockRandom(min: 0, max: 1),
            linearBlue: .mockRandom(min: 0, max: 1),
            opacity: .mockRandom(min: 0, max: 1)
        )
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension ResolvedPaint: AnyMockable, RandomMockable {
    public static func mockAny() -> ResolvedPaint {
        return ResolvedPaint(paint: .mockAny())
    }

    public static func mockRandom() -> ResolvedPaint {
        return ResolvedPaint(paint: .mockRandom())
    }
}

// MARK: GraphicsImage
@available(iOS 13.0, tvOS 13.0, *)
extension GraphicsImage.Contents: Equatable {
    public static func == (lhs: GraphicsImage.Contents, rhs: GraphicsImage.Contents) -> Bool {
        switch (lhs, rhs) {
        case let (.cgImage(lImage), .cgImage(rImage)):
            return lImage === rImage
        case (.unknown, .unknown):
            return true
        default:
            return false
        }
    }
}

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
        width: Int = .mockImageDimension(),
        scale: CGFloat = 1.0
    ) -> CGImage {
        precondition(width > 0, "Width must be greater than 0")

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: width),
            format: format
        )

        let image = renderer.image { context in
            // Fill with a random color
            let randomColor = UIColor(
                red: CGFloat.random(in: 0...1),
                green: CGFloat.random(in: 0...1),
                blue: CGFloat.random(in: 0...1),
                alpha: 1.0
            )
            randomColor.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: width, height: width)))
        }

        guard let cgImage = image.cgImage else {
            fatalError("Failed to create CGImage from UIGraphicsImageRenderer")
        }

        return cgImage
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
