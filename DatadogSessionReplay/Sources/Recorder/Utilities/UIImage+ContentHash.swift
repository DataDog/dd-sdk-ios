/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import CryptoKit
import UIKit

private var contentHashKey: UInt8 = 0
private let contentHashColorSpace = CGColorSpace(name: CGColorSpace.sRGB)
private let contentHashBitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
private let hexadecimalDigits = Array("0123456789abcdef".utf8)

extension UIImage {
    /// A cached hash of the image's pixel content and dimensions.
    ///
    /// Image scale and orientation metadata do not affect the hash.
    /// Returns `nil` if the image has no backing `CGImage` or its pixels cannot be prepared.
    internal var contentHash: String? {
        if let hash = objc_getAssociatedObject(self, &contentHashKey) as? String {
            return hash
        }

        guard let hash = cgImage?.computeContentHash() else {
            return nil
        }

        objc_setAssociatedObject(self, &contentHashKey, hash, .OBJC_ASSOCIATION_RETAIN)
        return hash
    }
}

extension CGImage {
    fileprivate func computeContentHash() -> String? {
        guard width > 0, height > 0 else {
            return nil
        }

        // The direct path must use the same sRGB BGRA8 pixels as the drawing path to produce the same hash
        if hasContentHashPixelFormat,
           let data = dataProvider?.data,
           CFDataGetLength(data) >= width * 4,
           // Check the last logical row without overflowing when the provider has a large stride.
           (CFDataGetLength(data) - width * 4) / bytesPerRow >= height - 1,
           let pixels = CFDataGetBytePtr(data) {
            return withExtendedLifetime(data) {
                hashContent(pixels, width: width, height: height, bytesPerRow: bytesPerRow)
            }
        }

        guard let context = makeContentHashContext(), let pixels = context.data else {
            return nil
        }

        return withExtendedLifetime(context) {
            hashContent(pixels, width: context.width, height: context.height, bytesPerRow: context.bytesPerRow)
        }
    }

    private var hasContentHashPixelFormat: Bool {
        return width <= 100
            && height <= 100
            && !isMask
            && decode == nil
            && bitsPerComponent == 8
            && bitsPerPixel == 32
            && bitmapInfo.rawValue == contentHashBitmapInfo
            && colorSpace?.name == CGColorSpace.sRGB
            && bytesPerRow >= width * 4
    }

    func makeContentHashContext() -> CGContext? {
        let scale = min(1, 100 / Double(max(width, height)))
        // Keep at least one pixel on each axis for very wide or tall images
        let thumbnailWidth = max(1, Int((Double(width) * scale).rounded()))
        let thumbnailHeight = max(1, Int((Double(height) * scale).rounded()))
        // Align rows to 16 bytes for Core Graphics. Padding is excluded from the digest
        let bytesPerRow = (thumbnailWidth * 4 + 15) & ~15

        guard
            let colorSpace = contentHashColorSpace,
            let context = CGContext(
                data: nil,
                width: thumbnailWidth,
                height: thumbnailHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: contentHashBitmapInfo
            )
        else {
            return nil
        }

        context.interpolationQuality = .low
        context.setBlendMode(.copy)
        context.draw(self, in: CGRect(x: 0, y: 0, width: thumbnailWidth, height: thumbnailHeight))
        return context
    }

    func hashContent(_ pixels: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) -> String {
        var hasher = SHA256()

        var originalWidth = UInt64(self.width).littleEndian
        var originalHeight = UInt64(self.height).littleEndian

        withUnsafeBytes(of: &originalWidth) {
            hasher.update(bufferPointer: $0)
        }
        withUnsafeBytes(of: &originalHeight) {
            hasher.update(bufferPointer: $0)
        }

        let logicalBytesPerRow = width * 4

        if bytesPerRow == logicalBytesPerRow {
            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: pixels, count: logicalBytesPerRow * height))
        } else {
            for row in 0..<height {
                hasher.update(
                    bufferPointer: UnsafeRawBufferPointer(
                        start: pixels.advanced(by: row * bytesPerRow),
                        count: logicalBytesPerRow
                    )
                )
            }
        }

        return hasher.finalize().withUnsafeBytes { digest in
            String(unsafeUninitializedCapacity: digest.count * 2) { buffer in
                for (index, byte) in digest.enumerated() {
                    buffer[index * 2] = hexadecimalDigits[Int(byte >> 4)]
                    buffer[index * 2 + 1] = hexadecimalDigits[Int(byte & 0x0f)]
                }
                return buffer.count
            }
        }
    }
}
#endif
