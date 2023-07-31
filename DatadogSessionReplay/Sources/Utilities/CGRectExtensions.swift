/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import CoreGraphics

internal extension CGRect {
    enum HorizontalAlignment {
        case left, right, center
    }

    enum VerticalAlignment {
        case top, bottom, middle
    }

    /// Puts this rect inside other rect with given alignment.
    func putInside(
        _ other: CGRect,
        horizontalAlignment: HorizontalAlignment,
        verticalAlignment: VerticalAlignment
    ) -> CGRect {
        var new = self

        switch horizontalAlignment {
        case .left:     new.origin.x = other.minX
        case .right:    new.origin.x = other.maxX - new.size.width
        case .center:   new.origin.x = other.minX + (other.size.width - new.size.width) * 0.5
        }

        switch verticalAlignment {
        case .top:      new.origin.y = other.minY
        case .bottom:   new.origin.y = other.maxY - new.size.height
        case .middle:   new.origin.y = other.minY + (other.size.height - new.size.height) * 0.5
        }

        return new
    }
}
