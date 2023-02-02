/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

extension UIImage {
    func compressToTargetSize(_ targetSize: Int) -> Data? {
        var compressionQuality: CGFloat = 1.0
        guard var imageData = pngData() else {
            return nil
        }
        guard imageData.count >= targetSize else {
            return imageData
        }
        var image = self
        while imageData.count > targetSize {
            compressionQuality -= 0.1
            imageData = image.jpegData(compressionQuality: compressionQuality)!

            if imageData.count > targetSize {
                image = image.scaledImage(by: 0.9)
            }
        }
        return imageData 
    }

    func scaledImage(by percentage: CGFloat) -> UIImage {
        let newSize = CGSize(width: size.width * percentage, height: size.height * percentage)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { (context) in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
