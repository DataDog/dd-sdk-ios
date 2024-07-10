/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

extension UIImage {
    /// Scales down the image to an approximate file size in bytes.
    ///
    /// - Parameter desiredSizeInBytes: The target file size in bytes.
    /// - Returns: A Data object representing the scaled down image as PNG data.
    ///
    /// This function takes the desired file size in bytes as input and scales down the image iteratively
    /// until the resulting PNG data size is less than or equal to the specified target size.
    ///
    /// Note: The function will return the original image data if it is already smaller than the desired size,
    /// or if it fails to generate a smaller image.
    ///
    /// Example usage:
    ///
    ///     let originalImage = UIImage(named: "exampleImage")
    ///     let desiredSizeInBytes = 10240 // 10 KB
    ///     if let imageData = originalImage?.scaledDownToApproximateSize(desiredSizeInBytes) {
    ///         // Use the scaled down image data.
    ///     }
    func scaledDownToApproximateSize(_ desiredSizeInBytes: UInt64, tint: UIColor? = nil) -> Data {
        guard let imageData = pngData() else {
            return Data()
        }
        guard tint != nil || imageData.count > desiredSizeInBytes else {
            return imageData
        }
        // Initial scale is approximatation based on the average side of square for given size ratio.
        // When running experiments it appeared to be closer to desired scale than using just a size ratio.
        let initialScale = min(1, sqrt(CGFloat(desiredSizeInBytes) / CGFloat(imageData.count)))
        var scaledImage = scaledImage(by: initialScale, tint: tint)

        var scale: Double = 1
        let maxIterations = 20
        for _ in 0...maxIterations {
            guard let scaledImageData = scaledImage.pngData() else {
                return imageData
            }
            if scaledImageData.count <= desiredSizeInBytes {
                return scaledImageData
            }
            scale *= 0.9
            scaledImage = scaledImage.scaledImage(by: scale, tint: tint)
        }
        guard let scaledImageData = scaledImage.pngData() else {
            return imageData
        }
        return scaledImageData.count < imageData.count ? scaledImageData : imageData
    }

    /// Scales the image by a given percentage.
    ///
    /// - Parameter percentage: The scaling factor to apply, where 1.0 represents the original size.
    /// - Returns: A UIImage object representing the scaled image, or an empty UIImage if the percentage is less than or equal to zero.
    ///
    /// This private helper function takes a CGFloat percentage as input and scales the image accordingly.
    /// It ensures that the resulting image has a size proportional to the original one, maintaining its aspect ratio.
    private func scaledImage(by percentage: CGFloat, tint: UIColor?) -> UIImage {
        guard percentage > 0 else {
            return UIImage()
        }
        let newSize = CGSize(width: size.width * percentage, height: size.height * percentage)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        let drawRect = CGRect(origin: .zero, size: newSize)
        if let tint = tint {
            tint.setFill()
            UIRectFill(drawRect)
        }
        draw(in: drawRect, blendMode: .destinationIn, alpha: 1.0)
        let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return scaledImage ?? UIImage()
    }
}

#endif
