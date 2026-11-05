/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import ImageIO
import TestUtilities
import Testing
import UIKit

@testable import DatadogSessionReplay

@Suite(.datadogTesting)
struct UIImagePNGTests {
    @Test
    func preservesDisplayP3ColorsWithoutResizing() throws {
        // Given
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let pixels: [UInt8] = [255, 64, 0, 255, 128, 32, 0, 128]
        let image = try #require(UIImage(pixels: pixels, width: 2, height: 1, colorSpace: colorSpace))

        // When
        let data = try #require(image.resizedPNGData())

        // Then
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 2)
        #expect(decoded.height == 1)
        #expect(decoded.bitsPerComponent == 8)
        #expect(decoded.colorSpace?.name == CGColorSpace.displayP3)

        let context = try #require(
            CGContext(
                data: nil,
                width: 2,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 8,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(decoded, in: CGRect(x: 0, y: 0, width: 2, height: 1))
        let output = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
        withExtendedLifetime(context) {
            #expect(Array(UnsafeBufferPointer(start: output, count: pixels.count)) == pixels)
        }
    }
}
#endif
