/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS) && canImport(SwiftUI)
import Foundation
import SwiftUI

@available(iOS 13.0, *)
extension SwiftUI.Color {
    /// The `SwiftUI.Color.Resolved` has been made public in iOS 17.
    /// It's reflected by `SwiftUI.Color._Resolved` to avoid name conflict.
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

@available(iOS 13.0, *)
extension SwiftUI.Color._Resolved {
    var cgColor: CGColor {
        CGColor(
            red: CGFloat(linearRed),
            green: CGFloat(linearGreen),
            blue: CGFloat(linearBlue),
            alpha: CGFloat(opacity)
        )
    }
}

#endif
