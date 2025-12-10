/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal extension UIViewController {
    /// The canonical class name for this view controller.
    /// If this `UIViewController` class is defined in Swift module, it will be prefixed by the module name, e.g. `Foo.CheckoutViewController`. 
    var canonicalClassName: String {
        return NSStringFromClass(type(of: self))
    }

    /// `true` if the view controller is an instance of `UIAlertController` or one of its subclasses,
    /// `false` otherwise.
    var isUIAlertController: Bool {
        self is UIAlertController
    }
}

internal extension UIView {
    /// Traverses the hierarchy of this view from bottom-up to find any parent view matching
    /// the given predicate. It starts from `self`.
    func findInParentHierarchy(viewMatching predicate: (UIView) -> Bool) -> UIView? {
        if predicate(self) {
            return self
        } else if let superview = superview {
            return superview.findInParentHierarchy(viewMatching: predicate)
        } else {
            return nil
        }
    }

    /// Determines if capturing this view is safe for user privacy
    @objc var isSafeForPrivacy: Bool {
        guard let window = self.window else {
            return false // The view is invisible, we can't determine if it's safe
        }
        guard !NSStringFromClass(type(of: window)).contains("Keyboard") else {
            return false // The window class name suggests that it's the on-screen keyboard
        }
        return true
    }

    @objc var isSwiftUIView: Bool {
        return NSStringFromClass(type(of: self)).contains("SwiftUI")
    }

    /// `true` if this view is a button in a `UIAlertController`, `false` otherwise.
    var isUIAlertActionView: Bool {
        guard let actionViewClass = NSClassFromString("_UIAlertControllerActionView"),
              self.isKind(of: actionViewClass) else {
            return false
        }
        return true
    }

    /// `true` if this view is a text field in a `UIAlertController`, `false` otherwise.
    var isUIAlertTextField: Bool {
        guard let alertTextFieldClass = NSClassFromString("_UIAlertControllerTextField"),
              self.isKind(of: alertTextFieldClass) else {
            return false
        }
        return true
    }
}
