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
    @Test("Returns placeholder when image should not be sent")
    func returnsPlaceholderWhenImageShouldNotBeSent() throws {
        // Given
        let redactor = ImageRedactor()
        let image = UIImage()

        // When
        let result = try redactor.redact(image, action: .placeholder)

        // Then
        #expect(result.isPlaceholder)
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

    var isPlaceholder: Bool {
        guard case .placeholder = self else {
            return false
        }

        return true
    }
}
#endif
