/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import TestUtilities
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import DatadogSessionReplay

@Suite(.datadogTesting)
struct ImageSnapshotResourceTests {
    @Test(arguments: [ImageSnapshotResource.Format.png, .webP])
    func identifierChangesWhenEncodedDimensionsChange(format: ImageSnapshotResource.Format) throws {
        // Given
        let image = try #require(
            UIImage(
                pixels: [UInt8](repeating: 0, count: 1_500 * 6 * 4),
                width: 1_500,
                height: 6,
                scale: 3
            )
        )
        let cgImage = try #require(image.cgImage)
        let scaledImage = UIImage(cgImage: cgImage, scale: 1, orientation: .up)

        // When
        let identifier = ImageSnapshotResource(image: image, format: format).calculateIdentifier()
        let scaledIdentifier = ImageSnapshotResource(image: scaledImage, format: format).calculateIdentifier()

        // Then
        #expect(!identifier.isEmpty)
        #expect(!scaledIdentifier.isEmpty)
        #expect(identifier != scaledIdentifier)
    }

    @Test(arguments: [ImageSnapshotResource.Format.png, .webP])
    func identifierMatchesAcrossScalesWhenEncodedDimensionsMatch(format: ImageSnapshotResource.Format) throws {
        // Given
        let image = try #require(
            UIImage(
                pixels: [UInt8](repeating: 0, count: 1_500 * 6 * 4),
                width: 1_500,
                height: 6,
                scale: 3
            )
        )
        let cgImage = try #require(image.cgImage)
        let scaledImage = UIImage(cgImage: cgImage, scale: 2, orientation: .up)

        // When
        let identifier = ImageSnapshotResource(image: image, format: format).calculateIdentifier()
        let scaledIdentifier = ImageSnapshotResource(image: scaledImage, format: format).calculateIdentifier()

        // Then
        #expect(!identifier.isEmpty)
        #expect(!scaledIdentifier.isEmpty)
        #expect(identifier == scaledIdentifier)
    }

    @Test(arguments: [ImageSnapshotResource.Format.png, .webP], [CGFloat(1), 2, 3])
    func encodesRequestedFormatWithMatchingDimensions(format: ImageSnapshotResource.Format, scale: CGFloat) throws {
        // Given
        let image = try #require(
            UIImage(
                pixels: [UInt8](repeating: 0, count: 1_500 * 6 * 4),
                width: 1_500,
                height: 6,
                scale: scale
            )
        )
        let resource = ImageSnapshotResource(image: image, format: format)

        // When
        let data = resource.calculateData()

        // Then
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let expectedType: UTType = format == .png ? .png : .webP
        let expectedMIMEType = format == .png ? "image/png" : "image/webp"
        let expectedSuffix = format == .png ? ".png" : ".webp"
        let expectedWidth = scale == 1 ? 1_000 : 1_500
        let expectedHeight = scale == 1 ? 4 : 6
        #expect(CGImageSourceGetType(source) as String? == expectedType.identifier)
        #expect(resource.mimeType == expectedMIMEType)
        #expect(decoded.width == expectedWidth)
        #expect(decoded.height == expectedHeight)
        #expect(resource.calculateIdentifier().hasSuffix("-\(decoded.width)x\(decoded.height)\(expectedSuffix)"))
    }

    @Test
    func identifierDistinguishesFormatsForTheSameImage() throws {
        // Given
        let image = try #require(UIImage(pixels: [255, 0, 0, 255], width: 1, height: 1))
        let png = ImageSnapshotResource(image: image, format: .png)
        let webP = ImageSnapshotResource(image: image, format: .webP)

        // When
        let pngIdentifier = png.calculateIdentifier()
        let webPIdentifier = webP.calculateIdentifier()

        // Then
        #expect(!pngIdentifier.isEmpty)
        #expect(!webPIdentifier.isEmpty)
        #expect(pngIdentifier != webPIdentifier)
        #expect(pngIdentifier.dropLast(4) == webPIdentifier.dropLast(5))
    }
}
#endif
