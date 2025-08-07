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

/// Mapping SwiftUI orientation to UIImage orientation
@available(iOS 13.0, tvOS 13.0, *)
internal extension UIImage.Orientation {
    init(_ orientation: SwiftUI.Image.Orientation) {
        switch orientation {
        case .up: self = UIImage.Orientation.up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        }
    }
}
#endif
