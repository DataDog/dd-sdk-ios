/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import QuartzCore

@available(iOS 13.0, tvOS 13.0, *)
extension CALayer {
    var isBarBackground: Bool {
        delegate?.isKind(of: Classes.barBackground) == true
    }

    var isGlassGroup: Bool {
        delegate?.isKind(of: Classes.glassGroupView) == true
    }

    var isLiquidLens: Bool {
        delegate?.isKind(of: Classes.liquidLensView) == true
    }

    var isVisualEffectBackground: Bool {
        delegate?.isKind(of: Classes.visualEffectBackgroundView) == true
    }

    var isVisualEffectBackdrop: Bool {
        isKind(of: Classes.backdropLayer)
    }
}

private enum Classes {
    static let barBackground: AnyClass? = NSClassFromString("_UIBarBackground")
    static let glassGroupView: AnyClass? = NSClassFromString("UIKit._GlassGroupView")
    static let liquidLensView: AnyClass? = NSClassFromString("_UILiquidLensView")
    static let visualEffectBackgroundView: AnyClass? = NSClassFromString("_UIVisualEffectBackgroundView")
    static let backdropLayer: AnyClass? = NSClassFromString("UICABackdropLayer")
}

extension NSObjectProtocol {
    fileprivate func isKind(of aClass: AnyClass?) -> Bool {
        guard let aClass else {
            return false
        }
        return isKind(of: aClass)
    }
}
#endif
