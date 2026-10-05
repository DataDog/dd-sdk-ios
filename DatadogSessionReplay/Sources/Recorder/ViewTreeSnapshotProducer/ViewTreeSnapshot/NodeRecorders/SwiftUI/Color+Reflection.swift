/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import Foundation
import SwiftUI
import DatadogInternal

extension SwiftUI.Color._Resolved: Reflection {
    init(from reflector: Reflector) throws {
        linearRed = try reflector.descendant("linearRed")
        linearGreen = try reflector.descendant("linearGreen")
        linearBlue = try reflector.descendant("linearBlue")
        opacity = try reflector.descendant("opacity")
    }
}

extension SwiftUI.Color._ResolvedHDR: Reflection {
    init(from reflector: Reflector) throws {
        base = try reflector.descendant("base")
        _headroom = try reflector.descendant("_headroom")
    }
}

extension ColorView: Reflection {
    init(from reflector: Reflector) throws {
        color = try reflector.descendant("color")
    }
}

extension ResolvedPaint: Reflection {
    init(from reflector: Reflector) throws {
        if #available(iOS 26, tvOS 26, *) {
            paint = reflector.descendantIfPresent(type: ColorView.self, "paint")?.color.base
        } else {
            paint = reflector.descendantIfPresent("paint")
        }
    }
}

#endif
