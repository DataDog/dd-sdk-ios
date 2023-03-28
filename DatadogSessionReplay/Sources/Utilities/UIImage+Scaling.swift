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
    func scaledDownToApproximateSize(_ maxSizeInBytes: Int, _ maxIterations: Int = 20) -> Data {
        guard let imageData = pngData() else {
            return Data()
        }
        guard imageData.count >= maxSizeInBytes else {
            return imageData
        }
        let percentage: CGFloat = CGFloat(maxSizeInBytes) / CGFloat(imageData.count)
        var scaledData = scaledImage(by: percentage)?.pngData() ?? Data()

        var iterations = 0, scale: Double = 1
        while scaledData.count > maxSizeInBytes && iterations < maxIterations {
            scale *= 0.9
            let newScaledData = scaledImage(by: scale)?.pngData() ?? Data()
            if newScaledData.count <= scaledData.count {
                scaledData = newScaledData
            }
            iterations += 1
        }
        return scaledData.count < imageData.count ? scaledData : imageData
    }

    private func scaledImage(by percentage: CGFloat) -> UIImage? {
        let newSize = CGSize(width: size.width * percentage, height: size.height * percentage)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1)
        draw(in: CGRect(origin: .zero, size: newSize))
        let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return scaledImage
    }
}

