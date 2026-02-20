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

    init(handler: UIScrollViewScrollHandler) throws {
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
        private let handler: UIScrollViewScrollHandler

        /// Proxies keyed by scroll view identity to avoid double-wrapping.
        private var proxies: [ObjectIdentifier: UIScrollViewDelegateProxy] = [:]
        private let lock = NSLock()

        init(handler: UIScrollViewScrollHandler) throws {
            self.method = try dd_class_getInstanceMethod(UIScrollView.self, Self.selector)
            self.handler = handler
        }

        func swizzle() {
            typealias Signature = @convention(block) (UIScrollView, UIScrollViewDelegate?) -> Void
            swizzle(method) { previousImplementation -> Signature in
                return { [weak handler = self.handler, weak self] scrollView, delegate in
                    guard let handler = handler, let self = self else {
                        previousImplementation(scrollView, Self.selector, delegate)
                        return
                    }

                    // Don't re-wrap if the delegate is already our proxy
                    if delegate is UIScrollViewDelegateProxy {
                        previousImplementation(scrollView, Self.selector, delegate)
                        return
                    }

                    let proxy = UIScrollViewDelegateProxy(
                        originalDelegate: delegate,
                        handler: handler
                    )

                    self.lock.lock()
                    self.proxies[ObjectIdentifier(scrollView)] = proxy
                    self.lock.unlock()

                    let delegateType = delegate.map { String(describing: type(of: $0)) } ?? "nil"
                    DD.logger.debug("🔄 [ScrollTracking] Wrapping delegate \(delegateType) on \(type(of: scrollView))")
                    previousImplementation(scrollView, Self.selector, proxy)
                }
            }
        }
    }
}

#endif
