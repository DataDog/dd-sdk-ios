/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import Foundation
import SwiftUI

@available(iOS 13.0, tvOS 13.0, *)
extension SwiftUI.Color._Resolved: Reflection {
    init(_ mirror: ReflectionMirror) throws {
        linearRed = try mirror.descendant("linearRed")
        linearGreen = try mirror.descendant("linearGreen")
        linearBlue = try mirror.descendant("linearBlue")
        opacity = try mirror.descendant("opacity")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension ResolvedPaint: Reflection {
    init(_ mirror: ReflectionMirror) throws {
        paint = try? mirror.descendant("paint")
    }
}

#endif
