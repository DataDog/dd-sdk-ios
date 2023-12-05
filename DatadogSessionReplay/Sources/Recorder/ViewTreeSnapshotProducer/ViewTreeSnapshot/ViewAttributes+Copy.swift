/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

extension ViewAttributes {
    /// struct copy, lets you overwrite specific variables retaining the value of the rest
    /// using a closure to set the new values for the copy of the struct
    func copy(_ build: (inout Builder) -> Void) -> ViewAttributes {
        var builder = Builder(original: self)
        build(&builder)
        return builder.toViewAttributes()
    }

    struct Builder {
        var frame: CGRect
        var backgroundColor: CGColor?
        var layerBorderColor: CGColor?
        var layerBorderWidth: CGFloat
        var layerCornerRadius: CGFloat
        var alpha: CGFloat
        var isHidden: Bool
        var intrinsicContentSize: CGSize

        fileprivate init(original: ViewAttributes) {
            self.frame = original.frame
            self.backgroundColor = original.backgroundColor
            self.layerBorderColor = original.layerBorderColor
            self.layerBorderWidth = original.layerBorderWidth
            self.layerCornerRadius = original.layerCornerRadius
            self.alpha = original.alpha
            self.isHidden = original.isHidden
            self.intrinsicContentSize = original.intrinsicContentSize
        }

        fileprivate func toViewAttributes() -> ViewAttributes {
            return ViewAttributes(
                frame: frame,
                backgroundColor: backgroundColor,
                layerBorderColor: layerBorderColor,
                layerBorderWidth: layerBorderWidth,
                layerCornerRadius: layerCornerRadius,
                alpha: alpha,
                isHidden: isHidden,
                intrinsicContentSize: intrinsicContentSize
            )
        }
    }
}
#endif
