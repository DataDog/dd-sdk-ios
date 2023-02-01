/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

extension UIImage {
    func compressToTargetSize(_ targetSize: Int) -> Data? {
        var compressionQuality: CGFloat = 1.0
        var imageData = jpegData(compressionQuality: compressionQuality)!
        var image = self
        while imageData.count > targetSize {
            compressionQuality -= 0.2
            imageData = image.jpegData(compressionQuality: compressionQuality)!

            if imageData.count > targetSize {
                let newSize = CGSize(width: image.size.width * 0.8, height: image.size.height * 0.8)
                image = image.resizedImage(to: newSize)
            }
        }
        return imageData
    }

    func resizedImage(to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { (context) in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
