/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import TestUtilities
import Testing
import UIKit

@testable import DatadogSessionReplay

@Suite(.datadogTesting)
struct ImageSnapshotResourceTests {
    @Test
    func identifierChangesWhenEncodedDimensionsChange() throws {
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
        let identifier = ImageSnapshotResource(image: image).calculateIdentifier()
        let scaledIdentifier = ImageSnapshotResource(image: scaledImage).calculateIdentifier()

        // Then
        #expect(!identifier.isEmpty)
        #expect(!scaledIdentifier.isEmpty)
        #expect(identifier != scaledIdentifier)
    }

    @Test
    func identifierMatchesAcrossScalesWhenEncodedDimensionsMatch() throws {
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
        let identifier = ImageSnapshotResource(image: image).calculateIdentifier()
        let scaledIdentifier = ImageSnapshotResource(image: scaledImage).calculateIdentifier()

        // Then
        #expect(!identifier.isEmpty)
        #expect(!scaledIdentifier.isEmpty)
        #expect(identifier == scaledIdentifier)
    }
}
#endif
