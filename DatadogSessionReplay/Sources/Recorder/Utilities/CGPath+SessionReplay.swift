/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import CoreGraphics
import DatadogInternal
import Foundation

#if $RetroactiveAttribute
extension CGPath: @retroactive DatadogExtended {}
#else
extension CGPath: DatadogExtended {}
#endif

extension DatadogExtension where ExtendedType: CGPath {
    var svgString: String {
        var d = ""
        type.applyWithBlock { pointer in
            let element = pointer.pointee
            let points = element.points

            switch element.type {
            case .moveToPoint:
                d += "M \(points[0].dd.svgString) "
            case .addLineToPoint:
                d += "L \(points[0].dd.svgString) "
            case .addQuadCurveToPoint:
                d += "Q \(points[0].dd.svgString) \(points[1].dd.svgString) "
            case .addCurveToPoint:
                d += "C \(points[0].dd.svgString) \(points[1].dd.svgString) \(points[2].dd.svgString) "
            case .closeSubpath:
                d += "Z "
            @unknown default:
                break
            }
        }
        return d.trimmingCharacters(in: .whitespaces)
    }
}

#if $RetroactiveAttribute
extension CGPoint: @retroactive DatadogExtended {}
#else
extension CGPoint: DatadogExtended {}
#endif

extension DatadogExtension where ExtendedType == CGPoint {
    fileprivate var svgString: String {
        String(format: "%.3f %.3f", type.x, type.y)
    }
}

#endif
