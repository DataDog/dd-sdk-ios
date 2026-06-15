/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Testing
import UIKit

@testable import DatadogSessionReplay

struct ImageRedactorTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Returns the original image when no redaction is needed")
    func returnsOriginalImageWhenNoRedactionIsNeeded() throws {
        // Given
        let redactor = ImageRedactor()
        let image = UIImage()

        // When
        let result = try redactor.redact(image, action: .none)

        // Then
        let redactedImage = try #require(result.image)
        #expect(redactedImage === image)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Returns placeholder with background color when image should not be sent")
    func returnsPlaceholderWithBackgroundColorWhenImageShouldNotBeSent() throws {
        // Given
        let redactor = ImageRedactor()
        let image = UIImage.mockWith(color: .red)

        // When
        let result = try redactor.redact(image, action: .placeholder)

        // Then
        let backgroundColor = try #require(result.backgroundColor)
        #expect(backgroundColor == .red)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private extension ImageRedactionResult {
    var image: UIImage? {
        guard case let .image(image) = self else {
            return nil
        }

        return image
    }

    var backgroundColor: UIColor? {
        guard case let .placeholder(backgroundColor) = self else {
            return nil
        }

        return backgroundColor
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private extension UIImage {
    static func mockWith(color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
    }
}
#endif
