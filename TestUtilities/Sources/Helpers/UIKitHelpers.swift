/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import UIKit

/// The library name for UIKit framework as it will appear in unsymbolicated stack trace.
///
/// This name may differ between OS runtimes.
public var uiKitLibraryName: String {
    let uiKitBundleURL = Bundle(for: UIViewController.self).bundleURL
    let uiKitFrameworkName = uiKitBundleURL.lastPathComponent // 'UIKitCore.framework' on iOS 12+; 'UIKit.framework' on iOS 11
    return String(uiKitFrameworkName.dropLast(".framework".count))
}

extension UIView {
    /// Obtains a list of all the subviews, recursively, including `self`, that match a given predicate.
    ///
    /// Example usage:
    ///
    /// `view.allSubviewsMatching(predicate: { %0 is UITextField })` returns a
    /// list of all the views in `view` subview hierarchy, including itself, that are `UITextField`.
    ///
    /// `view.allSubviewsMatching(predicate: { _ in true })` returns a list of the entire
    /// subview hierarchy of `view`, including itself.
    ///
    /// No assumptions should be made about the order of the returned views.
    ///
    /// - parameters:
    ///     - predicate: returns `true` if the given view should be included in the result, `false` otherwise.
    ///
    /// - returns: An array with all `self` subviews (including `self`) that match the given predicate.
    public func allSubviewsMatching(predicate: (UIView) -> Bool) -> [UIView] {
        var queue = [self]
        var result = [UIView]()

        while let view = queue.popLast() {
            if predicate(view) {
                result.append(view)
            }

            queue.append(contentsOf: view.subviews)
        }

        return result
    }
}
#endif
