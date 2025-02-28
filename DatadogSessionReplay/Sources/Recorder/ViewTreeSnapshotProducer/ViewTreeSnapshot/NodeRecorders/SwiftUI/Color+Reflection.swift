/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import Foundation
import SwiftUI
import DatadogInternal

@available(iOS 13.0, tvOS 13.0, *)
extension SwiftUI.Color._Resolved: Reflection {
    init(from reflector: Reflector) throws {
        linearRed = try reflector.descendant("linearRed")
        linearGreen = try reflector.descendant("linearGreen")
        linearBlue = try reflector.descendant("linearBlue")
        opacity = try reflector.descendant("opacity")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension ResolvedPaint: Reflection {
    init(from reflector: Reflector) throws {
        paint = reflector.descendantIfPresent("paint")
    }
}

#endif
