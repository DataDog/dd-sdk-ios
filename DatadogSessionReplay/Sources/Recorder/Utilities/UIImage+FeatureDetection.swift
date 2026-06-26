/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit
import Vision

extension UIImage {
    func textRectangles() throws -> [CGRect] {
        let targetImage = if imageRendererFormat.opaque {
            self
        } else {
            // Composite transparent images over a contrasting background so Vision can detect text
            UIGraphicsImageRenderer(size: size, format: imageRendererFormat).image { context in
                let foregroundColor = dominantColor ?? .black
                let backgroundColor = foregroundColor.luminance < 0.5 ? UIColor.white : .black

                backgroundColor.setFill()
                UIRectFill(CGRect(origin: .zero, size: size))
                draw(at: .zero)
            }
        }

        let request = VNDetectTextRectanglesRequest()
        request.reportCharacterBoxes = false

        try targetImage.performFeatureDetection(with: request)

        guard let results = request.results else {
            return []
        }

        return results
            .map(\.boundingBox)
            .map(convertFromBoundingBox)
    }
}

extension UIImage {
    fileprivate func performFeatureDetection(with request: VNRequest) throws {
        guard let cgImage else {
            struct MissingCGImage: Error {}
            throw MissingCGImage()
        }

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: .init(imageOrientation)
        )

        try handler.perform([request])
    }

    fileprivate func convertFromBoundingBox(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX * size.width,
            y: (1 - rect.maxY) * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
    }
}

extension CGImagePropertyOrientation {
    fileprivate init(_ uiImageOrientation: UIImage.Orientation) {
        switch uiImageOrientation {
        case .up:
            self = .up
        case .down:
            self = .down
        case .left:
            self = .left
        case .right:
            self = .right
        case .upMirrored:
            self = .upMirrored
        case .downMirrored:
            self = .downMirrored
        case .leftMirrored:
            self = .leftMirrored
        case .rightMirrored:
            self = .rightMirrored
        default:
            self = .up
        }
    }
}

extension UIColor {
    fileprivate var luminance: CGFloat {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0

        self.getRed(&r, green: &g, blue: &b, alpha: nil)

        // Approximate perceived brightness to choose a contrasting background
        return (0.299 * r) + (0.587 * g) + (0.114 * b)
    }
}
#endif
