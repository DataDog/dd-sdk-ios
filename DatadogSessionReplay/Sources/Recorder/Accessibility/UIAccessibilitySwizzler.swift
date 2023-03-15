/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal protocol UIAccessibilityHandler: AnyObject {
    func notify_ElementDidBecomeFocused(element: NSObject)
    func notify_ElementDidLoseFocus(element: NSObject)
    func notify_GetElementAccessibilityLabel(element: NSObject)
}

internal class NOPAccessibilityHandler: UIAccessibilityHandler {
    func notify_ElementDidBecomeFocused(element: NSObject) {}
    func notify_ElementDidLoseFocus(element: NSObject) {}

    /// 💡 Intercepting this with a breakpoint is nice for inspecting the internal call stack from `Accessibility` framework.
    func notify_GetElementAccessibilityLabel(element: NSObject) {}
}

/// PoC - experimental swizzler to understand more on how `Accessibility` framework reads AX info.
internal final class UIAccessibilitySwizzler {
    let elementDidBecomeFocused: ElementDidBecomeFocused
    let elementDidLoseFocus: ElementDidLoseFocus
    let getAccessibilityLabel: GetAccessibilityLabel

    init() throws {
        let handler = NOPAccessibilityHandler()
        elementDidBecomeFocused = try ElementDidBecomeFocused(handler: handler)
        elementDidLoseFocus = try ElementDidLoseFocus(handler: handler)
        getAccessibilityLabel = try GetAccessibilityLabel(handler: handler)
    }

    func swizzle() {
        elementDidBecomeFocused.swizzle()
        elementDidLoseFocus.swizzle()
        getAccessibilityLabel.swizzle()
    }

    internal func unswizzle() {
        elementDidBecomeFocused.unswizzle()
        elementDidLoseFocus.unswizzle()
        getAccessibilityLabel.unswizzle()
    }

    // MARK: - Swizzlings

    /// Swizzles the `NSObject.accessibilityElementDidBecomeFocused()`
    class ElementDidBecomeFocused: MethodSwizzler <
        @convention(c) (NSObject, Selector) -> Bool,
        @convention(block) (NSObject) -> Bool
    > {
        private static let selector = NSSelectorFromString("accessibilityElementDidBecomeFocused")
        private let method: FoundMethod
        private let handler: UIAccessibilityHandler

        init(handler: UIAccessibilityHandler) throws {
            self.method = try Self.findMethod(with: Self.selector, in: NSObject.self)
            self.handler = handler
        }

        func swizzle() {
            typealias Signature = @convention(block) (NSObject) -> Bool
            swizzle(method) { previousImplementation -> Signature in
                return { [weak handler = self.handler] element  in
                    handler?.notify_ElementDidBecomeFocused(element: element)
                    return previousImplementation(element, Self.selector)
                }
            }
        }
    }

    /// Swizzles the `NSObject.accessibilityElementDidLoseFocus()`
    class ElementDidLoseFocus: MethodSwizzler <
        @convention(c) (NSObject, Selector) -> Bool,
        @convention(block) (NSObject) -> Bool
    > {
        private static let selector = NSSelectorFromString("accessibilityElementDidLoseFocus")
        private let method: FoundMethod
        private let handler: UIAccessibilityHandler

        init(handler: UIAccessibilityHandler) throws {
            self.method = try Self.findMethod(with: Self.selector, in: NSObject.self)
            self.handler = handler
        }

        func swizzle() {
            typealias Signature = @convention(block) (NSObject) -> Bool
            swizzle(method) { previousImplementation -> Signature in
                return { [weak handler = self.handler] element  in
                    handler?.notify_ElementDidLoseFocus(element: element)
                    return previousImplementation(element, Self.selector)
                }
            }
        }
    }

    class GetAccessibilityLabel: MethodSwizzler <
        @convention(c) (NSObject, Selector) -> Bool,
        @convention(block) (NSObject) -> Bool
    > {
        private static let selector = NSSelectorFromString("accessibilityLabel")
        private let method: FoundMethod
        private let handler: UIAccessibilityHandler

        init(handler: UIAccessibilityHandler) throws {
            self.method = try Self.findMethod(with: Self.selector, in: NSObject.self)
            self.handler = handler
        }

        func swizzle() {
            typealias Signature = @convention(block) (NSObject) -> Bool
            swizzle(method) { previousImplementation -> Signature in
                return { [weak handler = self.handler] element  in
                    handler?.notify_GetElementAccessibilityLabel(element: element)
                    return previousImplementation(element, Self.selector)
                }
            }
        }
    }
}
