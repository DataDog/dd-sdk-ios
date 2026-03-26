/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(tvOS)

import UIKit
import DatadogInternal

/// Swizzles `UIScrollView.delegate` setter and getter to wrap delegates with a tracking proxy
/// while keeping the proxy invisible to app code.
/// This enables automatic detection of scroll and swipe gestures on UIScrollView-based
/// components (UITableView, UICollectionView, UIScrollView).
internal final class UIScrollViewSwizzler {
    let setDelegate: SetDelegate
    let getDelegate: GetDelegate

    init(handler: UIScrollViewHandler) throws {
        setDelegate = try SetDelegate(handler: handler)
        let getMethod = try dd_class_getInstanceMethod(UIScrollView.self, #selector(getter: UIScrollView.delegate))
        getDelegate = GetDelegate(method: getMethod)
    }

    func swizzle() {
        setDelegate.swizzle()
        getDelegate.swizzle()
    }

    func unswizzle() {
        setDelegate.unswizzle()
        getDelegate.unswizzle()
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

        /// Associated object key for storing the proxy on the original delegate.
        /// The proxy's lifetime is tied to the delegate's lifetime: when the delegate is
        /// deallocated, the proxy is released too, and `scrollView.delegate` (a weak property)
        /// naturally becomes nil — preventing UIKit from calling the proxy after the
        /// original delegate is gone.
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

                    // If setting delegate to nil, just forward — the proxy will be
                    // released naturally when the previous delegate is deallocated.
                    guard let delegate = delegate else {
                        previousImplementation(scrollView, Self.selector, nil)
                        return
                    }

                    // Don't re-wrap if the delegate is already our proxy
                    if delegate is UIScrollViewDelegateProxy {
                        previousImplementation(scrollView, Self.selector, delegate)
                        return
                    }

                    // Check if this delegate already has a proxy attached to it
                    if let existingProxy = objc_getAssociatedObject(delegate, &Self.proxyKey) as? UIScrollViewDelegateProxy {
                        // Reuse the existing proxy but update the handler in case RUM was
                        // stopped and re-enabled (a new handler instance would be active).
                        existingProxy.handler = handler
                        previousImplementation(scrollView, Self.selector, existingProxy)
                    } else {
                        // Create a new proxy and attach it to the delegate.
                        // The proxy's lifetime is tied to the delegate's lifetime, so when
                        // the delegate is deallocated the proxy goes with it and
                        // scrollView.delegate naturally becomes nil.
                        let proxy = UIScrollViewDelegateProxy(
                            originalDelegate: delegate,
                            handler: handler
                        )
                        objc_setAssociatedObject(
                            delegate,
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

    /// Swizzles `UIScrollView.delegate` getter to return the original delegate
    /// instead of the internal tracking proxy.
    class GetDelegate: MethodSwizzler<
        @convention(c) (UIScrollView, Selector) -> UIScrollViewDelegate?,
        @convention(block) (UIScrollView) -> UIScrollViewDelegate?
    > {
        private static let selector = #selector(getter: UIScrollView.delegate)
        private let method: Method

        init(method: Method) {
            self.method = method
        }

        func swizzle() {
            typealias Signature = @convention(block) (UIScrollView) -> UIScrollViewDelegate?
            swizzle(method) { previousImplementation -> Signature in
                return { scrollView in
                    let delegate = previousImplementation(scrollView, Self.selector)
                    if let proxy = delegate as? UIScrollViewDelegateProxy {
                        return proxy.originalDelegate
                    }
                    return delegate
                }
            }
        }
    }
}

#endif
