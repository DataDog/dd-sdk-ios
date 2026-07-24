/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import QuartzCore
import UIKit

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

    var isPortal: Bool {
        isKind(of: Classes.portalLayer)
    }

    var isSignedDistanceField: Bool {
        isKind(of: Classes.sdfLayer) || isKind(of: Classes.sdfElementLayer)
    }

    var isDestinationOutView: Bool {
        hasViewDelegateClass {
            NSStringFromClass($0).hasSuffix("DestOutView")
        }
    }

    var isNavigationBarPlatter: Bool {
        delegate?.isKind(of: Classes.navigationBarPlatterView) == true
    }

    var isPlatformGlassInteraction: Bool {
        hasViewDelegateClass {
            NSStringFromClass($0).hasSuffix("UIPlatformGlassInteractionView")
        }
    }

    var isTabBarPlatter: Bool {
        delegate?.isKind(of: Classes.tabBarPlatterView) == true
    }

    var isScrollPocket: Bool {
        delegate?.isKind(of: Classes.scrollPocket) == true
    }

    var isCaptureOnlyBackdrop: Bool {
        guard
            isKind(of: Classes.backdropLayer),
            let captureOnly = safeValue(forKey: "captureOnly") as? Bool
        else {
            return false
        }

        return captureOnly
    }

    var isVisualEffectBackground: Bool {
        delegate?.isKind(of: Classes.visualEffectBackgroundView) == true
    }

    var isVisualEffectBackdrop: Bool {
        isKind(of: Classes.visualEffectBackdropLayer)
    }

    private func hasViewDelegateClass(matching predicate: (AnyClass) -> Bool) -> Bool {
        guard
            let view = delegate as? UIView,
            Bundle(for: type(of: view)) == Bundle(for: UIView.self)
        else {
            return false
        }
        return predicate(type(of: view))
    }
}

private enum Classes {
    static let barBackground: AnyClass? = NSClassFromString("_UIBarBackground")
    static let glassGroupView: AnyClass? = NSClassFromString("UIKit._GlassGroupView")
    static let liquidLensView: AnyClass? = NSClassFromString("_UILiquidLensView")
    static let portalLayer: AnyClass? = NSClassFromString("CAPortalLayer")
    static let sdfLayer: AnyClass? = NSClassFromString("CASDFLayer")
    static let sdfElementLayer: AnyClass? = NSClassFromString("CASDFElementLayer")
    static let navigationBarPlatterView: AnyClass? = NSClassFromString("_UINavigationBarPlatterView")
    static let tabBarPlatterView: AnyClass? = NSClassFromString("UIKit._UITabBarPlatterView")
    static let scrollPocket: AnyClass? = NSClassFromString("_UIScrollPocket")
    static let backdropLayer: AnyClass? = NSClassFromString("CABackdropLayer")
    static let visualEffectBackgroundView: AnyClass? = NSClassFromString("_UIVisualEffectBackgroundView")
    static let visualEffectBackdropLayer: AnyClass? = NSClassFromString("UICABackdropLayer")
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
