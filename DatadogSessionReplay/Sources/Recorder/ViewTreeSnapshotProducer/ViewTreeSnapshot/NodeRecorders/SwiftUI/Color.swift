/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import SwiftUI

@available(iOS 13.0, *)
extension SwiftUI.Color {
    struct _Resolved {
        let linearRed: Float
        let linearGreen: Float
        let linearBlue: Float
        let opacity: Float
    }
}

@available(iOS 13.0, *)
internal struct ResolvedPaint {
    let paint: SwiftUI.Color._Resolved
}

@available(iOS 13.0, *)
extension SwiftUI.Color._Resolved: Reflection {
    init(_ mirror: Mirror) throws {
        linearRed = try mirror.descendant(path: "linearRed")
        linearGreen = try mirror.descendant(path: "linearGreen")
        linearBlue = try mirror.descendant(path: "linearBlue")
        opacity = try mirror.descendant(path: "opacity")
    }
}

@available(iOS 13.0, *)
extension ResolvedPaint: Reflection {
    init(_ mirror: Mirror) throws {
        paint = try mirror.descendant(path: "paint")
    }
}

//=================================================================================

@available(iOS 13.0, *)
extension SwiftUI.Color._Resolved: Reflection_ {
    init(_ mirror: ReflectionMirror) throws {
        linearRed = try mirror.get(name: "linearRed")
        linearGreen = try mirror.get(name: "linearGreen")
        linearBlue = try mirror.get(name: "linearBlue")
        opacity = try mirror.get(name: "opacity")
    }
}

@available(iOS 13.0, *)
extension ResolvedPaint: Reflection_ {
    init(_ mirror: ReflectionMirror) throws {
        paint = try mirror.get(name: "paint")
    }
}
