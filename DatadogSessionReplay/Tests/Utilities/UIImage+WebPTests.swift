/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import TestUtilities
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import DatadogSessionReplay

@Suite(.datadogTesting)
struct UIImageWebPTests {
    @Test(arguments: [CGFloat(1), 2, 3], [false, true])
    func preservesPixelDimensionsAndRowOrder(scale: CGFloat, resizing: Bool) throws {
        // Given
        let width = 64
        let height = 32
        let red: [UInt8] = [255, 0, 0, 255]
        let blue: [UInt8] = [0, 0, 255, 255]
        let pixels = (0..<height).flatMap { row in
            Array(repeating: row < height / 2 ? red : blue, count: width).flatMap { $0 }
        }
        let image = try #require(
            UIImage(pixels: pixels, width: width, height: height, scale: scale)
        )

        // When
        let maxSize = resizing ? CGSize(width: 16, height: 16) : CGSize(width: 1_000, height: 1_000)
        let data = try #require(image.webPData(maxSize: maxSize))

        // Then
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.webP.identifier)
        let decoded = try #require(CGImage.make(data: data))
        #expect(decoded.width == (resizing ? Int(16 * scale) : width))
        #expect(decoded.height == (resizing ? Int(8 * scale) : height))
        let output = try #require(decoded.premultipliedRGBA())
        let top = try #require(output.first)
        let bottom = try #require(output.last)
        let colorTolerance = 15
        #expect(abs(Int(top.red) - 255) <= colorTolerance)
        #expect(Int(top.blue) <= colorTolerance)
        #expect(Int(bottom.red) <= colorTolerance)
        #expect(abs(Int(bottom.blue) - 255) <= colorTolerance)
    }

    @Test(arguments: [true, false])
    func preservesTransparency(premultiplied: Bool) throws {
        // Given
        let alphaValues: [UInt8] = [0, 128, 255]
        let pixels = alphaValues.flatMap { alpha -> [UInt8] in
            [premultiplied ? alpha : .max, 0, 0, alpha]
        }
        let alphaInfo: CGImageAlphaInfo = premultiplied ? .premultipliedLast : .last
        let image = try #require(
            UIImage(
                pixels: pixels,
                width: alphaValues.count,
                height: 1,
                bitmapInfo: .byteOrder32Big.union(
                    CGBitmapInfo(rawValue: alphaInfo.rawValue)
                )
            )
        )

        // When
        let data = try #require(image.webPData())

        // Then
        let output = try #require(CGImage.make(data: data)?.premultipliedRGBA())
        #expect(output.map { $0.alpha } == alphaValues)
        let halfOpacityRed = output[1]
        let colorTolerance = 3
        #expect(abs(Int(halfOpacityRed.red) - 128) <= colorTolerance)
        #expect(Int(halfOpacityRed.green) <= colorTolerance)
        #expect(Int(halfOpacityRed.blue) <= colorTolerance)
    }

    @Test
    func normalizesByteOrderAndRowPadding() throws {
        // Given
        let width = 16
        let height = 8
        let bgra: [UInt8] = [30, 60, 120, 128]
        let padding = [UInt8](repeating: 255, count: 16)
        let paddedRow = Array(repeating: bgra, count: width).flatMap { $0 } + padding
        let image = try #require(
            UIImage(
                pixels: Array(repeating: paddedRow, count: height).flatMap { $0 },
                width: width,
                height: height,
                bytesPerRow: paddedRow.count,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.union(
                    CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                )
            )
        )

        // When
        let data = try #require(image.webPData())

        // Then
        let output = try #require(CGImage.make(data: data)?.premultipliedRGBA())
        let secondRowPixel = output[width]
        let expected = (
            red: 120,
            green: 60,
            blue: 30,
            alpha: UInt8(128)
        )
        let colorTolerance = 4
        #expect(abs(Int(secondRowPixel.red) - expected.red) <= colorTolerance)
        #expect(abs(Int(secondRowPixel.green) - expected.green) <= colorTolerance)
        #expect(abs(Int(secondRowPixel.blue) - expected.blue) <= colorTolerance)
        #expect(secondRowPixel.alpha == expected.alpha)
    }

    @Test(arguments: [CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast], [false, true])
    func encodesOpaqueImages(alphaInfo: CGImageAlphaInfo, resizing: Bool) throws {
        // Given
        let inputPixel: [UInt8] = switch alphaInfo {
        case .noneSkipFirst: [0, 120, 60, 30]
        case .noneSkipLast: [120, 60, 30, 0]
        default: [120, 60, 30]
        }
        let width = 16
        let height = 8
        let row = Array(repeating: inputPixel, count: width).flatMap { $0 }
        let byteOrder: CGBitmapInfo = alphaInfo == .none ? .byteOrderDefault : .byteOrder32Big
        let image = try #require(
            UIImage(
                pixels: Array(repeating: row, count: height).flatMap { $0 },
                width: width,
                height: height,
                bitsPerPixel: inputPixel.count * UInt8.bitWidth,
                bitmapInfo: byteOrder.union(
                    CGBitmapInfo(rawValue: alphaInfo.rawValue)
                )
            )
        )

        // When
        let data = try #require(
            image.webPData(maxSize: resizing ? CGSize(width: 8, height: 4) : image.size)
        )

        // Then
        let pixel = try #require(CGImage.make(data: data)?.premultipliedRGBA()?.first)
        let expected = (red: 120, green: 60, blue: 30)
        let colorTolerance = 4
        #expect(abs(Int(pixel.red) - expected.red) <= colorTolerance)
        #expect(abs(Int(pixel.green) - expected.green) <= colorTolerance)
        #expect(abs(Int(pixel.blue) - expected.blue) <= colorTolerance)
        #expect(pixel.alpha == 255)
    }

    @Test
    func convertsGrayscaleImages() throws {
        // Given
        let image = try #require(
            UIImage(
                pixels: [UInt8](repeating: 128, count: 16 * 16),
                width: 16,
                height: 16,
                bitsPerPixel: 8,
                colorSpace: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: []
            )
        )
        let expected = try #require(image.cgImage?.premultipliedRGBA()?.first)

        // When
        let data = try #require(image.webPData())

        // Then
        let pixel = try #require(CGImage.make(data: data)?.premultipliedRGBA()?.first)
        let colorTolerance = 3
        let neutralTolerance = 2
        #expect(pixel.alpha == 255)
        #expect(
            abs(
                Int(pixel.red) - Int(pixel.green)
            ) <= neutralTolerance
        )
        #expect(
            abs(
                Int(pixel.green) - Int(pixel.blue)
            ) <= neutralTolerance
        )
        #expect(
            abs(
                Int(pixel.red) - Int(expected.red)
            ) <= colorTolerance
        )
    }

    @Test(arguments: [false, true])
    func convertsDisplayP3ToSRGB(resizing: Bool) throws {
        // Given
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let color: [UInt8] = [120, 160, 50, 255]
        let image = try #require(
            UIImage(
                pixels: Array(repeating: color, count: 16 * 16).flatMap { $0 },
                width: 16,
                height: 16,
                colorSpace: colorSpace
            )
        )
        let expected = try #require(image.cgImage?.premultipliedRGBA()?.first)

        // When
        let data = try #require(
            image.webPData(maxSize: resizing ? CGSize(width: 8, height: 8) : image.size)
        )

        // Then
        let pixel = try #require(CGImage.make(data: data)?.premultipliedRGBA()?.first)
        let colorTolerance = 4
        #expect(
            abs(
                Int(pixel.red) - Int(expected.red)
            ) <= colorTolerance
        )
        #expect(
            abs(
                Int(pixel.green) - Int(expected.green)
            ) <= colorTolerance
        )
        #expect(
            abs(
                Int(pixel.blue) - Int(expected.blue)
            ) <= colorTolerance
        )
        #expect(pixel.alpha == 255)
    }

    @Test
    func encodedDataOutlivesSourceImage() throws {
        // Given
        let color: [UInt8] = [120, 60, 30, 128]
        let pixels = Array(repeating: color, count: 16 * 16).flatMap { $0 }

        // When
        let data = try autoreleasepool {
            let image = try #require(
                UIImage(pixels: pixels, width: 16, height: 16)
            )
            return try #require(
                image.webPData()
            )
        }

        // Then
        let decoded = try #require(CGImage.make(data: data))
        #expect(decoded.width == 16)
        #expect(decoded.height == 16)
        let pixel = try #require(decoded.premultipliedRGBA()?.first)
        #expect(pixel.alpha == 128)
    }

    @Test
    func preservesTransparencyWhenResizing() throws {
        // Given
        let pixel: [UInt8] = [128, 0, 0, 128]
        let image = try #require(
            UIImage(pixels: Array(repeating: pixel, count: 16 * 8).flatMap { $0 }, width: 16, height: 8)
        )

        // When
        let data = try #require(image.webPData(maxSize: CGSize(width: 8, height: 4)))

        // Then
        let decoded = try #require(CGImage.make(data: data))
        #expect(decoded.width == 8)
        #expect(decoded.height == 4)
        let output = try #require(decoded.premultipliedRGBA())
        let colorTolerance = 3
        #expect(
            output.allSatisfy {
                $0.alpha == 128
                && abs(Int($0.red) - 128) <= colorTolerance
                && Int($0.green) <= colorTolerance
                && Int($0.blue) <= colorTolerance
            }
        )
    }

    @Test(arguments: [(16_384, 1), (1, 16_384)])
    func encodesVeryWideAndTallImages(width: Int, height: Int) throws {
        // Given
        let image = try #require(
            UIImage(pixels: [UInt8](repeating: 0, count: width * height * 4), width: width, height: height)
        )

        // When
        let data = try #require(image.webPData())

        // Then
        let decoded = try #require(CGImage.make(data: data))
        #expect(decoded.width == (width > 1 ? 1_000 : 1))
        #expect(decoded.height == (height > 1 ? 1_000 : 1))
    }

    @Test(
        arguments: [
            CGSize.zero,
            CGSize(width: -1, height: 1),
            CGSize(width: CGFloat.nan, height: 1),
            CGSize(width: 1, height: CGFloat.infinity)
        ]
    )
    func rejectsInvalidMaximumSize(maxSize: CGSize) throws {
        // Given
        let image = try #require(UIImage(pixels: [255, 0, 0, 255], width: 1, height: 1))

        // When
        let data = image.webPData(maxSize: maxSize)

        // Then
        #expect(data == nil)
    }

    @Test(arguments: [(16_384, 1), (1, 16_384)])
    func rejectsOutputLargerThanWebPLimit(width: Int, height: Int) throws {
        // Given
        let image = try #require(
            UIImage(pixels: [UInt8](repeating: 0, count: width * height * 4), width: width, height: height)
        )

        // When
        let data = image.webPData(maxSize: CGSize(width: 16_384, height: 16_384))

        // Then
        #expect(data == nil)
    }

    @Test(arguments: [false, true])
    func returnsNilWithoutCGImage(coreImageBacked: Bool) {
        // Given
        let image: UIImage
        if coreImageBacked {
            let ciImage = CIImage(color: .red).cropped(
                to: CGRect(x: 0, y: 0, width: 16, height: 16)
            )
            image = UIImage(ciImage: ciImage)
        } else {
            image = UIImage()
        }

        // When
        let data = image.webPData()

        // Then
        #expect(data == nil)
    }
}

fileprivate extension CGImage {
    static func make(data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func premultipliedRGBA() -> [(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)]? {
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }
        context.setBlendMode(.copy)
        context.draw(
            self,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }
        return withExtendedLifetime(context) {
            stride(from: 0, to: context.bytesPerRow * height, by: 4).map { offset in
                (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
            }
        }
    }
}
#endif
