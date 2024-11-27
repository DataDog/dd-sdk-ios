/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import CoreGraphics
import SwiftUI

/// Represents a SwiftUI.GraphicsImage
@available(iOS 13.0, tvOS 13.0, *)
internal struct GraphicsImage {
    let contents: Contents
    let scale: CGFloat
    let orientation: SwiftUI.Image.Orientation

    enum Contents {
        case cgImage(CGImage)
        case unknown
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension GraphicsImage.Contents: Equatable {
    static func == (lhs: GraphicsImage.Contents, rhs: GraphicsImage.Contents) -> Bool {
        switch (lhs, rhs) {
        case let (.cgImage(lImage), .cgImage(rImage)):
            return lImage === rImage
        case (.unknown, .unknown):
            return true
        default:
            return false
        }
    }
}
#endif
