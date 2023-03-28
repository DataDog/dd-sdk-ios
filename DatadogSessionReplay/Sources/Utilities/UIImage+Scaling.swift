/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

extension UIImage {
    /**
     Returns a scaled version of the image that is approximately equal to the size specified by the `maxSizeInBytes` parameter.
     The approximate size is calculated based on the bitmap dimensions of the image,
     but does not take into account the size of the PNG header or any compression that may be applied.

     - Parameters:
         - maxSizeInBytes: The maximum size, in bytes, of the scaled image.

     - Returns: The data object containing the scaled image, or an empty data object if the image data cannot be converted to PNG data or if the scaled image cannot be converted to PNG data.
     */
    func scaledDownToApproximateSize(_ desiredSizeInBytes: Int) -> Data {
        guard let imageData = pngData() else {
            return Data()
        }
        guard imageData.count > desiredSizeInBytes else {
            return imageData
        }
        var scaledImage = scaledImage(by: CGFloat(desiredSizeInBytes) / CGFloat(imageData.count))

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
            scaledImage = scaledImage.scaledImage(by: scale)
        }
        guard let scaledImageData = scaledImage.pngData() else {
            return imageData
        }
        return scaledImageData.count < imageData.count ? scaledImageData : imageData
    }

    private func scaledImage(by percentage: CGFloat) -> UIImage {
        guard percentage > 0 else {
            return UIImage()
        }
        let newSize = CGSize(width: size.width * percentage, height: size.height * percentage)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        draw(in: CGRect(origin: .zero, size: newSize))
        let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return scaledImage ?? UIImage()
    }
}
