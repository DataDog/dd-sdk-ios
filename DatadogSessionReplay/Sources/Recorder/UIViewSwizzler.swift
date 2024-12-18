/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit
import DatadogInternal

internal protocol UIViewHandler: AnyObject {
    func notify_layoutSubviews(view: UIView)
}

internal class UIViewSwizzler {
    let layoutSubviews: LayoutSubviews

    init(handler: UIViewHandler) throws {
        self.layoutSubviews = try LayoutSubviews(handler: handler)
    }

    func swizzle() {
        layoutSubviews.swizzle()
    }

    internal func unswizzle() {
        layoutSubviews.unswizzle()
    }

    // MARK: - Swizzlings

    /// Swizzles the `UIView.didLayoutSubviews()`
    class LayoutSubviews: MethodSwizzler <
    @convention(c) (UIView, Selector) -> Void,
    @convention(block) (UIView) -> Void
    > {
        private static let selector = #selector(UIView.layoutSubviews)
        private let method: Method
        private let handler: UIViewHandler

        init(handler: UIViewHandler) throws {
            self.method = try dd_class_getInstanceMethod(UIView.self, Self.selector)
            self.handler = handler
        }

        func swizzle() {
            typealias Signature = @convention(block) (UIView) -> Void
            swizzle(method) { previousImplementation -> Signature in
                return { [weak handler = self.handler] view  in
                    previousImplementation(view, Self.selector)
                    handler?.notify_layoutSubviews(view: view)
                }
            }
        }
    }
}
#endif
