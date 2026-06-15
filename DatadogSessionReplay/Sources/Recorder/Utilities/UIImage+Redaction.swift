/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

extension UIImage {
    var redactionColor: UIColor {
        dominantColor ?? .black
    }

    func image(redactingRectangles rects: [CGRect], color: UIColor? = nil) -> UIImage {
        guard !rects.isEmpty else {
            return self
        }

        return UIGraphicsImageRenderer(size: size, format: imageRendererFormat).image { context in
            draw(at: .zero)
            (color ?? redactionColor).setFill()
            rects
                .map { $0.intersection(CGRect(origin: .zero, size: size)) }
                .filter { !$0.isNull }
                .forEach(UIRectFill)
        }
    }
}
#endif
