/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

internal class UIViewControllerSwizzler {
    let viewWillAppear: ViewWillAppear
    let viewWillDisappear: ViewWillDisappear

    init(handler: UIKitRUMViewsHandlerType) throws {
        self.viewWillAppear = try ViewWillAppear(handler: handler)
        self.viewWillDisappear = try ViewWillDisappear(handler: handler)
    }

    func swizzle() {
        viewWillAppear.swizzle()
        viewWillDisappear.swizzle()
    }

    // MARK: - Swizzlings

    /// Swizzles the `UIViewController.viewWillAppear()`
    class ViewWillAppear: MethodSwizzler <
        @convention(c) (UIViewController, Selector, Bool) -> Void,
        @convention(block) (UIViewController, Bool) -> Void
    > {
        private static let selector = #selector(UIViewController.viewWillAppear(_:))
        private let method: FoundMethod
        private let handler: UIKitRUMViewsHandlerType

        init(handler: UIKitRUMViewsHandlerType) throws {
            self.method = try Self.findMethod(with: Self.selector, in: UIViewController.self)
            self.handler = handler
        }

        func swizzle() {
            typealias Signature = @convention(block) (UIViewController, Bool) -> Void
            swizzle(method) { previousImplementation -> Signature in
                return { [weak handler = self.handler] vc, animated  in
                    handler?.notify_viewWillAppear(viewController: vc, animated: animated)
                    return previousImplementation(vc, Self.selector, animated)
                }
            }
        }
    }

    /// Swizzles the `UIViewController.viewWillDisappear()`
    class ViewWillDisappear: MethodSwizzler <
        @convention(c) (UIViewController, Selector, Bool) -> Void,
        @convention(block) (UIViewController, Bool) -> Void
    > {
        private static let selector = #selector(UIViewController.viewWillDisappear(_:))
        private let method: FoundMethod
        private let handler: UIKitRUMViewsHandlerType

        init(handler: UIKitRUMViewsHandlerType) throws {
            self.method = try Self.findMethod(with: Self.selector, in: UIViewController.self)
            self.handler = handler
        }

        func swizzle() {
            typealias Signature = @convention(block) (UIViewController, Bool) -> Void
            swizzle(method) { previousImplementation -> Signature in
                return { [weak handler = self.handler] vc, animated  in
                    handler?.notify_viewWillDisappear(viewController: vc, animated: animated)
                    return previousImplementation(vc, Self.selector, animated)
                }
            }
        }
    }
}
