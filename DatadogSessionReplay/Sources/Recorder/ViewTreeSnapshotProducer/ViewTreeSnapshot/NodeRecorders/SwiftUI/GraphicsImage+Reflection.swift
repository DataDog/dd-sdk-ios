/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import CoreGraphics
import SwiftUI
import DatadogInternal

@available(iOS 13.0, tvOS 13.0, *)
extension GraphicsImage: Reflection {
    init(from reflector: Reflector) throws {
        scale = try reflector.descendant("scale")
        orientation = try reflector.descendant("orientation")
        contents = try reflector.descendant("contents")
        if #available(iOS 26, tvOS 26, *) {
            maskColor = reflector.descendantIfPresent(type: Color._ResolvedHDR.self, "maskColor")?.base
        } else {
            maskColor = reflector.descendantIfPresent("maskColor")
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension GraphicsImage.Contents: Reflection {
    init(from reflector: Reflector) throws {
        switch (reflector.displayStyle, reflector.descendantIfPresent(0)) {
        case let (.enum("cgImage"), cgImage as CGImage):
            self = .cgImage(cgImage)
        case let (.enum("vectorLayer"), contents):
            self = try .vectorImage(reflector.reflect(contents))
        default:
            self = .unknown
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension GraphicsImage.VectorImage: Reflection {
    init(from reflector: Reflector) throws {
        location = try reflector.descendant("location")
        name = try reflector.descendant("name")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension GraphicsImage.Location: Reflection {
    init(from reflector: Reflector) throws {
        switch (reflector.displayStyle, reflector.descendantIfPresent(0)) {
        case let (.enum("bundle"), bundle as Bundle):
            self = .bundle(bundle)
        default:
            self = .unknown
        }
    }
}
#endif
