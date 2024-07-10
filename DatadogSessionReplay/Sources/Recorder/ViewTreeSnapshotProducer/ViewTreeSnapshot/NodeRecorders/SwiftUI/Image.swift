/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS) && canImport(SwiftUI)

import Foundation
import SwiftUI
import CoreGraphics

@available(iOS 13.0, *)
internal struct GraphicsImage {
    struct Contents {
        let cgImage: CGImage
    }

    let contents: Contents?
    let scale: CGFloat
    let unrotatedPixelSize: CGSize
    let orientation: SwiftUI.Image.Orientation
    let maskColor: SwiftUI.Color._Resolved?
    let interpolation: SwiftUI.Image.Interpolation
}

@available(iOS 13.0, *)
extension GraphicsImage: Reflection {
    init(_ mirror: Mirror) throws {
        contents = try mirror.descendant(path: "contents")
        scale = try mirror.descendant(path: "scale")
        unrotatedPixelSize = try mirror.descendant(path: "unrotatedPixelSize")
        orientation = try mirror.descendant(path: "orientation")
        maskColor = try mirror.descendant(path: "maskColor")
        interpolation = try mirror.descendant(path: "interpolation")
    }
}

@available(iOS 13.0, *)
extension GraphicsImage.Contents: Reflection {
    init(_ mirror: Mirror) throws {
        cgImage = try mirror.descendant(path: "cgImage")
    }
}

@available(iOS 13.0, *)
extension SwiftUI.Image.Orientation {
    var uiImageOrientation: UIImage.Orientation {
        switch self {
        case .up:           return .up
        case .upMirrored:   return .upMirrored
        case .down:         return .down
        case .downMirrored: return .downMirrored
        case .left:         return .left
        case .leftMirrored: return .leftMirrored
        case .right:        return .right
        case .rightMirrored: return .rightMirrored
        }
    }
}

@available(iOS 13.0, *)
extension GraphicsImage {
    var uiImage: UIImage? {
        contents.map {
            UIImage(
                cgImage: $0.cgImage,
                scale: scale,
                orientation: orientation.uiImageOrientation
            )
        }
    }
}

#endif
