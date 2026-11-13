/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import CoreImage
import TestUtilities
import Testing
import UIKit

@testable import DatadogSessionReplay

@Suite(.datadogTesting)
struct UIImageContentHashTests {
    private let bgra = CGBitmapInfo.byteOrder32Little.union(
        CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
    )

    @Test
    func hashesOriginalDimensionsAndSmallImagePixels() throws {
        // Given: red, translucent green, blue, and transparent pixels in row order.
        let image = try #require(
            UIImage(pixels: [0, 0, 255, 255, 0, 128, 0, 128, 255, 0, 0, 255, 0, 0, 0, 0], width: 2, height: 2, bitmapInfo: bgra)
        )

        // When
        let hash = try #require(image.contentHash)

        // Then
        #expect(hash == "016c9b94db81d9c1661e3602f20e5cbbfa8afe51de90b4417f79342b2c056ebf")
    }

    @Test(arguments: [
        (100, 1, "fce5258fe02219b41c7ad0c49f63b360c7051fca23f6cf73fa82811d07ffa19e"),
        (101, 1, "275aee15f703684f6f6857ed11095e907b03211d5d727cfba9130c5df5cc8c6f"),
        (10_001, 1, "89f07c4b779a74a21d42ee34aad0e051517182c75b8259de4acda7849d651f97"),
        (1, 10_001, "8e1321be0d8f946fc5fab7b4dfb3d306b8a03fc9280216c6dbe6e345a485143d"),
        (317, 113, "9cf6a8f19bc209238b25548483075b35056a9deab88abf42181cd8ab5bbe758b"),
        (113, 317, "d12baaef3471f2145525cda252e2c3380904087d78caa216d3e026e01dec3429")
    ])
    func capsLongestEdgeAndPreservesOriginalDimensions(width: Int, height: Int, expectedHash: String) throws {
        // Given
        let image = try #require(
            UIImage(pixels: [UInt8](repeating: 255, count: width * height * 4), width: width, height: height, bitmapInfo: bgra)
        )

        // When
        let hash = try #require(image.contentHash)

        // Then
        #expect(hash == expectedHash)
    }

    @Test(arguments: [3, 101])
    func normalizesChannelOrderAndIgnoresRowPadding(width: Int) throws {
        // Given
        let height = 2
        let rgbaRows: [[UInt8]] = [[128, 0, 0, 128], [0, 0, 255, 255]]
        let bgraRows: [[UInt8]] = [[0, 0, 128, 128], [255, 0, 0, 255]]
        let rgbaPixels = rgbaRows.flatMap { Array(repeating: $0, count: width).flatMap { $0 } }
        let bgraPixels = bgraRows.flatMap { Array(repeating: $0, count: width).flatMap { $0 } }
        let padding = [UInt8](repeating: 0xa5, count: 16)
        let paddedPixels = bgraRows.flatMap { Array(repeating: $0, count: width).flatMap { $0 } + padding }
        let original = try #require(
            UIImage(pixels: bgraPixels, width: width, height: height, bitmapInfo: bgra)
        )
        let reordered = try #require(
            UIImage(pixels: rgbaPixels, width: width, height: height)
        )
        let padded = try #require(
            UIImage(pixels: paddedPixels, width: width, height: height, bytesPerRow: width * 4 + padding.count, bitmapInfo: bgra)
        )

        // When
        let hash = try #require(original.contentHash)

        // Then
        #expect(try #require(reordered.contentHash) == hash)
        #expect(try #require(padded.contentHash) == hash)
    }

    @Test
    func includesColorAndAlphaInHash() throws {
        // Given
        let black = try #require(
            UIImage(pixels: [0, 0, 0, 255], width: 1, height: 1, bitmapInfo: bgra)
        )
        let red = try #require(
            UIImage(pixels: [0, 0, 255, 255], width: 1, height: 1, bitmapInfo: bgra)
        )
        let translucentBlack = try #require(
            UIImage(pixels: [0, 0, 0, 128], width: 1, height: 1, bitmapInfo: bgra)
        )

        // When
        let hash = try #require(black.contentHash)

        // Then
        #expect(try #require(red.contentHash) != hash)
        #expect(try #require(translucentBlack.contentHash) != hash)
    }

    @Test
    func normalizesStraightAlpha() throws {
        // Given
        let premultiplied = try #require(
            UIImage(pixels: [0, 0, 128, 128, 0, 0, 0, 0], width: 2, height: 1, bitmapInfo: bgra)
        )
        let straight = try #require(
            UIImage(
                pixels: [255, 0, 0, 128, 255, 0, 0, 0],
                width: 2,
                height: 1,
                bitmapInfo: .byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue))
            )
        )

        // When
        let hash = try #require(premultiplied.contentHash)

        // Then
        #expect(try #require(straight.contentHash) == hash)
    }

    @Test(arguments: [CGImageAlphaInfo.noneSkipFirst, .noneSkipLast])
    func normalizesOpaqueImages(alphaInfo: CGImageAlphaInfo) throws {
        // Given
        let pixel: [UInt8] = alphaInfo == .noneSkipFirst ? [0, 120, 60, 30] : [120, 60, 30, 0]
        let opaque = try #require(
            UIImage(
                pixels: pixel,
                width: 1,
                height: 1,
                bitmapInfo: .byteOrder32Big.union(CGBitmapInfo(rawValue: alphaInfo.rawValue))
            )
        )
        let premultiplied = try #require(
            UIImage(pixels: [30, 60, 120, 255], width: 1, height: 1, bitmapInfo: bgra)
        )

        // When
        let hash = try #require(premultiplied.contentHash)

        // Then
        #expect(try #require(opaque.contentHash) == hash)
    }

    @Test
    func convertsGrayscaleImages() throws {
        // Given
        let grayscale = try #require(
            UIImage(
                pixels: [0, 255],
                width: 2,
                height: 1,
                bitsPerPixel: 8,
                colorSpace: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: []
            )
        )
        let color = try #require(
            UIImage(pixels: [0, 0, 0, 255, 255, 255, 255, 255], width: 2, height: 1, bitmapInfo: bgra)
        )

        // When
        let hash = try #require(color.contentHash)

        // Then
        #expect(try #require(grayscale.contentHash) == hash)
    }

    @Test
    func interpretsColorSpaceBeforeHashing() throws {
        // Given
        let pixels: [UInt8] = [50, 160, 120, 255]
        let srgb = try #require(
            UIImage(pixels: pixels, width: 1, height: 1, bitmapInfo: bgra)
        )
        let space = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let displayP3 = try #require(
            UIImage(pixels: pixels, width: 1, height: 1, colorSpace: space, bitmapInfo: bgra)
        )

        // When
        let hash = try #require(srgb.contentHash)

        // Then
        #expect(try #require(displayP3.contentHash) != hash)
    }

    @Test(arguments: [CGFloat(1), 2, 3])
    func ignoresImageScale(scale: CGFloat) throws {
        // Given
        let original = try #require(
            UIImage(pixels: [UInt8](repeating: 255, count: 120 * 90 * 4), width: 120, height: 90, bitmapInfo: bgra)
        )
        let image = UIImage(cgImage: try #require(original.cgImage), scale: scale, orientation: .up)

        // When
        let hash = try #require(original.contentHash)

        // Then
        #expect(try #require(image.contentHash) == hash)
    }

    @Test
    func cachesContentHash() throws {
        final class UIImageSpy: UIImage, @unchecked Sendable {
            private(set) var cgImageReads = 0

            override var cgImage: CGImage? {
                cgImageReads += 1
                return super.cgImage
            }
        }

        // Given
        let original = try #require(
            UIImage(pixels: [UInt8](repeating: 255, count: 16), width: 2, height: 2, bitmapInfo: bgra)
        )
        let image = UIImageSpy(cgImage: try #require(original.cgImage))
        let hash = try #require(image.contentHash)
        let readsAfterCalculation = image.cgImageReads

        // When
        let cachedHash = try #require(image.contentHash)

        // Then
        #expect(cachedHash == hash)
        #expect(image.cgImageReads == readsAfterCalculation)
    }

    @Test(arguments: [false, true])
    func returnsNilWithoutCGImage(coreImageBacked: Bool) {
        // Given
        let image = coreImageBacked
            ? UIImage(ciImage: CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16)))
            : UIImage()

        // When
        let hash = image.contentHash

        // Then
        #expect(hash == nil)
    }
}
#endif
