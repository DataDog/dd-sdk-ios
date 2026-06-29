/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit
import CoreImage

private var dominantColorKey: UInt8 = 0

extension UIImage {
    var dominantColor: UIColor? {
        if let color = objc_getAssociatedObject(self, &dominantColorKey) as? UIColor {
            return color
        }

        let color = dominantColor(context: .sessionReplay)
        objc_setAssociatedObject(self, &dominantColorKey, color, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        return color
    }

    private func dominantColor(
        context: CIContext
    ) -> UIColor? {
        guard
            let inputImage = CIImage(image: self),
            let filter = CIFilter(name: "CIKMeans")
        else {
            return nil
        }

        filter.setValue(inputImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: inputImage.extent), forKey: "inputExtent")
        filter.setValue(1, forKey: "inputCount")

        guard let outputImage = filter.outputImage else {
            return nil
        }

        var pixels = [UInt8](repeating: 0, count: 4)

        context.render(
            outputImage.settingAlphaOne(in: outputImage.extent),
            toBitmap: &pixels,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )

        if pixels[0] == pixels[1], pixels[1] == pixels[2] {
            return UIColor(white: CGFloat(pixels[0]) / 255, alpha: 1)
        } else {
            return UIColor(
                red: CGFloat(pixels[0]) / 255,
                green: CGFloat(pixels[1]) / 255,
                blue: CGFloat(pixels[2]) / 255,
                alpha: 1
            )
        }
    }
}

extension CIContext {
    fileprivate static let sessionReplay = CIContext()
}
#endif
