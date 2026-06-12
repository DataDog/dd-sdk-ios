/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit
import CoreImage

extension UIImage {
    func dominantColor() -> UIColor? {
        return dominantColors(count: 1, context: .sessionReplay).first?.color
    }

    private func dominantColors(
        count: Int,
        context: CIContext
    ) -> [(color: UIColor, weight: CGFloat)] {
        guard count > 0 else {
            return []
        }

        guard
            let inputImage = CIImage(image: self),
            let filter = CIFilter(name: "CIKMeans")
        else {
            return []
        }

        filter.setValue(inputImage, forKey: kCIInputImageKey)
        filter.setValue(inputImage.extent, forKey: "inputExtent")
        filter.setValue(count, forKey: "inputCount")

        guard let outputImage = filter.outputImage else {
            return []
        }

        var pixels = [UInt8](repeating: 0, count: count * 4)

        context.render(
            outputImage,
            toBitmap: &pixels,
            rowBytes: count * 4,
            bounds: CGRect(x: 0, y: 0, width: count, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )

        var dominantColors: [(color: UIColor, weight: CGFloat)] = []

        for index in stride(from: 0, to: pixels.count, by: 4) {
            dominantColors.append(
                (
                    color: UIColor(
                        red: CGFloat(pixels[index]) / 255,
                        green: CGFloat(pixels[index + 1]) / 255,
                        blue: CGFloat(pixels[index + 2]) / 255,
                        alpha: 1
                    ),
                    weight: CGFloat(pixels[index + 3]) / 255
                )
            )
        }

        return dominantColors.sorted { lhs, rhs in
            lhs.weight > rhs.weight
        }
    }
}

extension CIContext {
    fileprivate static let sessionReplay = CIContext()
}
#endif
