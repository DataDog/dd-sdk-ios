/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import DatadogInternal
import Foundation
import SwiftUI

@available(iOS 13.0, *)
extension SwiftUI.Path: DatadogExtended {}

@available(iOS 13.0, *)
extension DatadogExtension where ExtendedType == SwiftUI.Path {
    var svgString: String {
        var d = ""
        type.forEach { element in
            switch element {
            case let .move(to):
                d += "M \(to.dd.svgString) "
            case let .line(to):
                d += "L \(to.dd.svgString) "
            case let .quadCurve(to, control):
                d += "Q \(control.dd.svgString) \(to.dd.svgString) "
            case let .curve(to, control1, control2):
                d += "C \(control1.dd.svgString) \(control2.dd.svgString) \(to.dd.svgString) "
            case .closeSubpath:
                d += "Z "
            }
        }
        return d.trimmingCharacters(in: .whitespaces)
    }
}

extension CGPoint: DatadogExtended {}

extension DatadogExtension where ExtendedType == CGPoint {
    internal var svgString: String {
        "\(type.x.dd.svgString) \(type.y.dd.svgString)"
    }
}

extension CGFloat: DatadogExtended {}

extension DatadogExtension where ExtendedType == CGFloat {
    internal var svgString: String {
        String(format: "%.3f", locale: .init(identifier: "en_US_POSIX"), type)
    }
}

#endif
