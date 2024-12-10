/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import CoreGraphics
import SwiftUI

@available(iOS 13.0, tvOS 13.0, *)
extension GraphicsImage: Reflection {
    init(_ mirror: ReflectionMirror) throws {
        scale = try mirror.descendant("scale")
        orientation = try mirror.descendant("orientation")
        contents = try mirror.descendant("contents")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension GraphicsImage.Contents: Reflection {
    init(_ mirror: ReflectionMirror) throws {
        switch (mirror.displayStyle, mirror.descendant(0)) {
        case let (.enum("cgImage"), cgImage as CGImage):
            self = .cgImage(cgImage)
        default:
            self = .unknown
        }
    }
}
#endif
