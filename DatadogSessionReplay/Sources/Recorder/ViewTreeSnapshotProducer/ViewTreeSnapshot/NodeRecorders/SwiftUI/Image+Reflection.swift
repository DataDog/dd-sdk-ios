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
    init(from reflector: Reflector) throws {
        scale = try reflector.descendant("scale")
        orientation = try reflector.descendant("orientation")
        contents = try reflector.descendant("contents")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension GraphicsImage.Contents: Reflection {
    init(from reflector: Reflector) throws {
        switch (reflector.displayStyle, reflector.descendantIfPresent(0)) {
        case let (.enum("cgImage"), cgImage as CGImage):
            self = .cgImage(cgImage)
        default:
            self = .unknown
        }
    }
}
#endif
