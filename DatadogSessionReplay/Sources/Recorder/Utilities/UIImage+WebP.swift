/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Accelerate
import UIKit

@_implementationOnly import DatadogWebP

extension UIImage {
    internal func webPData() -> Data? {
        cgImage?.webPData()
    }
}

private let webPDimension: ClosedRange<Int> = 1...Int(WEBP_MAX_DIMENSION)

extension CGImage {
    fileprivate func webPData() -> Data? {
        guard
            webPDimension.contains(self.width),
            webPDimension.contains(self.height)
        else {
            return nil
        }

        guard var config = webPConfig(), var picture = webPPicture() else {
            return nil
        }

        defer {
            dd_WebPPictureFree(&picture)
        }

        guard webPImport(into: &picture) != 0 else {
            return nil
        }

        var writer = WebPMemoryWriter()
        dd_WebPMemoryWriterInit(&writer)

        defer {
            dd_WebPMemoryWriterClear(&writer)
        }

        let result = withUnsafeMutablePointer(to: &writer) { writer in
            picture.writer = dd_WebPMemoryWrite
            picture.custom_ptr = UnsafeMutableRawPointer(writer)
            return dd_WebPEncode(&config, &picture)
        }

        guard result != 0, let bytes = writer.mem, writer.size > 0 else {
            return nil
        }

        let data = Data(
            bytesNoCopy: bytes,
            count: writer.size,
            deallocator: .custom { pointer, _ in
                dd_WebPFree(pointer)
            }
        )

        // Ownership moved to `data`
        writer.mem = nil

        return data
    }

    private func webPConfig() -> WebPConfig? {
        var config = WebPConfig()

        guard WebPConfigInit(&config) != 0 else {
            return nil
        }

        config.method = 3
        config.alpha_quality = 100
        config.thread_level = 0
        config.exact = 1

        return config
    }

    private func webPPicture() -> WebPPicture? {
        var picture = WebPPicture()

        guard WebPPictureInit(&picture) != 0 else {
            return nil
        }

        picture.width = Int32(self.width)
        picture.height = Int32(self.height)
        picture.use_argb = 1

        return picture
    }

    private func webPImport(into picture: inout WebPPicture) -> Int32 {
        let hasAlpha = switch self.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            false
        case .first, .premultipliedFirst, .last, .premultipliedLast, .alphaOnly:
            true
        @unknown default:
            true
        }

        let bytesPerPixel = hasAlpha ? 4 : 3
        let alphaInfo: CGImageAlphaInfo = hasAlpha ? .last : .none

        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let format = vImage_CGImageFormat(
                bitsPerComponent: UInt8.bitWidth,
                bitsPerPixel: bytesPerPixel * UInt8.bitWidth,
                colorSpace: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: alphaInfo.rawValue),
                renderingIntent: self.renderingIntent
            ),
            let buffer = try? vImage_Buffer(cgImage: self, format: format)
        else {
            return 0
        }

        defer {
            buffer.free()
        }

        return hasAlpha
            ? dd_WebPPictureImportRGBA(
                &picture,
                buffer.data.assumingMemoryBound(to: UInt8.self),
                Int32(buffer.rowBytes)
            )
            : dd_WebPPictureImportRGB(
                &picture,
                buffer.data.assumingMemoryBound(to: UInt8.self),
                Int32(buffer.rowBytes)
            )
    }
}
#endif
