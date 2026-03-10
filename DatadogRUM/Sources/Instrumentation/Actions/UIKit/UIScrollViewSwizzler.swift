/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(tvOS)

import UIKit
import DatadogInternal

/// Swizzles `UIScrollView.delegate` setter to wrap delegates with a tracking proxy.
/// This enables automatic detection of scroll and swipe gestures on UIScrollView-based
/// components (UITableView, UICollectionView, UIScrollView).
internal final class UIScrollViewSwizzler {
    let setDelegate: SetDelegate

    init(handler: UIScrollViewHandler) throws {
        setDelegate = try SetDelegate(handler: handler)
    }

    func swizzle() {
        setDelegate.swizzle()
    }

    func unswizzle() {
        setDelegate.unswizzle()
    }

    // MARK: - Swizzlings

    /// Swizzles `UIScrollView.delegate` setter.
    class SetDelegate: MethodSwizzler<
        @convention(c) (UIScrollView, Selector, UIScrollViewDelegate?) -> Void,
        @convention(block) (UIScrollView, UIScrollViewDelegate?) -> Void
    > {
        private static let selector = #selector(setter: UIScrollView.delegate)
        private let method: Method
        private let handler: UIScrollViewHandler

        /// Associated object key for storing the proxy on the scroll view.
        private static var proxyKey: Void?

        init(handler: UIScrollViewHandler) throws {
            self.method = try dd_class_getInstanceMethod(UIScrollView.self, Self.selector)
            self.handler = handler
        }

        func swizzle() {
            typealias Signature = @convention(block) (UIScrollView, UIScrollViewDelegate?) -> Void
            swizzle(method) { previousImplementation -> Signature in
                return { [weak handler = self.handler] scrollView, delegate in
                    guard let handler = handler else {
                        previousImplementation(scrollView, Self.selector, delegate)
                        return
                    }

                    // If setting delegate to nil, remove the proxy and set to nil
                    if delegate == nil {
                        objc_setAssociatedObject(scrollView, &Self.proxyKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                        previousImplementation(scrollView, Self.selector, nil)
                        return
                    }

                    // Don't re-wrap if the delegate is already our proxy
                    if delegate is UIScrollViewDelegateProxy {
                        previousImplementation(scrollView, Self.selector, delegate)
                        return
                    }

                    // Check if we already have a proxy attached to this scroll view
                    if let existingProxy = objc_getAssociatedObject(scrollView, &Self.proxyKey) as? UIScrollViewDelegateProxy {
                        // Reuse existing proxy, just update its original delegate
                        existingProxy.originalDelegate = delegate
                        previousImplementation(scrollView, Self.selector, existingProxy)
                    } else {
                        // Create new proxy and attach it to the scroll view
                        // The proxy's lifetime is now tied to the scroll view's lifetime
                        let proxy = UIScrollViewDelegateProxy(
                            originalDelegate: delegate,
                            handler: handler
                        )
                        objc_setAssociatedObject(
                            scrollView,
                            &Self.proxyKey,
                            proxy,
                            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                        )
                        previousImplementation(scrollView, Self.selector, proxy)
                    }
                }
            }
        }
    }
}

#endif
