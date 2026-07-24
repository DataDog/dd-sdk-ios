/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import QuartzCore

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot {
    /// Captured subset of Core Animation filters that affect layer rendering.
    enum Filter: Sendable, Equatable {
        case gaussianBlur(CGFloat)
        case colorMatrix(ColorMatrix)
        case vibrantColorMatrix(ColorMatrix)
        case saturate(CGFloat)
        case brightness(CGFloat)
        case multiplyColor(CGColor)

        case unknown(String)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.Filter {
    /// Reads a supported layer filter. Unknown enabled filters are kept by name.
    init?(_ filterValue: Any) {
        guard
            let filterClass = NSClassFromString(["CA", "Filter"].joined()),
            let filter = filterValue as? NSObject,
            type(of: filter).isSubclass(of: filterClass),
            filter.safeValue(forKey: "enabled") as? Bool == true,
            let name = filter.safeValue(forKey: "name") as? String
        else {
            return nil
        }

        switch name {
        case "gaussianBlur", "variableBlur":
            guard let radius = filter.safeValue(forKey: "inputRadius") as? CGFloat else {
                return nil
            }
            self = .gaussianBlur(radius)
        case "colorMatrix":
            guard let value = filter.safeValue(forKey: "inputColorMatrix") as? NSValue else {
                return nil
            }
            var colorMatrix = CALayerSnapshot.ColorMatrix()
            value.getValue(&colorMatrix)
            self = .colorMatrix(colorMatrix)
        case "vibrantColorMatrix":
            guard let value = filter.safeValue(forKey: "inputColorMatrix") as? NSValue else {
                return nil
            }
            var colorMatrix = CALayerSnapshot.ColorMatrix()
            value.getValue(&colorMatrix)
            self = .vibrantColorMatrix(colorMatrix)
        case "colorSaturate":
            guard let amount = filter.safeValue(forKey: "inputAmount") as? CGFloat else {
                return nil
            }
            self = .saturate(amount)
        case "colorBrightness":
            guard let amount = filter.safeValue(forKey: "inputAmount") as? CGFloat else {
                return nil
            }
            self = .brightness(amount)
        case "multiplyColor":
            guard let color = CGColor.safeCast(filter.safeValue(forKey: "inputColor")) else {
                return nil
            }
            self = .multiplyColor(color)
        default:
            self = .unknown(name)
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot {
    /// A 4-by-5 color transform matrix used by layer filters.
    struct ColorMatrix: Sendable, Equatable {
        var m11: Float = 1
        var m12: Float = 0
        var m13: Float = 0
        var m14: Float = 0
        var m15: Float = 0

        var m21: Float = 0
        var m22: Float = 1
        var m23: Float = 0
        var m24: Float = 0
        var m25: Float = 0

        var m31: Float = 0
        var m32: Float = 0
        var m33: Float = 1
        var m34: Float = 0
        var m35: Float = 0

        var m41: Float = 0
        var m42: Float = 0
        var m43: Float = 0
        var m44: Float = 1
        var m45: Float = 0
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot {
    struct CompositingFilter: Sendable, Hashable, RawRepresentable {
        let rawValue: String

        init(rawValue: String) {
            self.rawValue = rawValue
        }

        init?(_ value: Any) {
            guard let rawValue = value as? String else {
                return nil
            }
            self.init(rawValue: rawValue)
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.CompositingFilter {
    static let normal = Self(rawValue: "normalBlendMode")
    static let plusDarker = Self(rawValue: "plusD")
    static let destinationIn = Self(rawValue: "destIn")
}
#endif
