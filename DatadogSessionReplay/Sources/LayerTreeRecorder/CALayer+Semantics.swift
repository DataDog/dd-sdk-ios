/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import QuartzCore
import UIKit

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

    var isScrollEdgeEffect: Bool {
        delegate?.isKind(of: Classes.scrollEdgeEffectView) == true
    }

    @MainActor var scrollPocketEdge: UIRectEdge? {
        var next = superlayer

        while let parent = next {
            if let scrollView = parent.delegate as? UIScrollView {
                let frame = convert(bounds, to: parent)
                let tolerance = 1 / max(scrollView.traitCollection.displayScale, 1)

                guard
                    !frame.isEmpty, !frame.isInfinite,
                    !parent.bounds.isEmpty, !parent.bounds.isInfinite,
                    frame.height < parent.bounds.height,
                    abs(frame.minX - parent.bounds.minX) <= tolerance,
                    abs(frame.maxX - parent.bounds.maxX) <= tolerance
                else {
                    return nil
                }

                let isTop = abs(frame.minY - parent.bounds.minY) <= tolerance
                let isBottom = abs(frame.maxY - parent.bounds.maxY) <= tolerance

                guard isTop != isBottom else {
                    return nil
                }

                return isTop ? .top : .bottom
            }

            next = parent.superlayer
        }

        return nil
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
        guard isKind(of: Classes.backdropLayer) else {
            return false
        }

        return superlayer?.delegate is UIVisualEffectView
            || delegate?.isKind(of: Classes.tabSelectionView) == true
            || superlayer?.delegate?.isKind(of: Classes.tabSelectionView) == true
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
    static let scrollEdgeEffectView: AnyClass? = NSClassFromString("UIKit.ScrollEdgeEffectView")
    static let backdropLayer: AnyClass? = NSClassFromString("CABackdropLayer")
    static let visualEffectBackgroundView: AnyClass? = NSClassFromString("_UIVisualEffectBackgroundView")
    static let tabSelectionView: AnyClass? = NSClassFromString("_UITabSelectionView")
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
