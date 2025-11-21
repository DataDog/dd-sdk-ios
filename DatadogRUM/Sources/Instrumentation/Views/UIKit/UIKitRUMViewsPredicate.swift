/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogInternal

/// Protocol defining the predicate for UIKit view controller tracking in RUM.
///
/// The SDK uses this predicate to determine whether a `UIViewController` should be
/// tracked as a RUM view. When a view controller appears, the SDK asks this predicate
/// whether to track it and how to represent it in the RUM Explorer.
///
/// Implement this protocol to customize which view controllers are tracked and how they
/// appear in the RUM Explorer.
public protocol UIKitRUMViewsPredicate {
    /// Converts a `UIViewController` into RUM view parameters, or filters it out.
    ///
    /// - Parameter viewController: The view controller that has appeared in the UI.
    /// - Returns: RUM view parameters if the view controller should be tracked, or `nil` to ignore it.
    func rumView(for viewController: UIViewController) -> RUMView?
}

/// Default implementation of `UIKitRUMViewsPredicate`.
///
/// This implementation tracks view controllers with their class names as view names.
/// System container controllers from UIKit are automatically filtered out.
public struct DefaultUIKitRUMViewsPredicate: UIKitRUMViewsPredicate {
    public init () {}

    public func rumView(for viewController: UIViewController) -> RUMView? {
        guard !Bundle(for: type(of: viewController)).dd_isUIKit else {
            // Part of our heuristic for (auto) tracking view controllers is to ignore
            // container view controllers coming from `UIKit` if they are not subclassed.
            // This condition is wider and it ignores all view controllers defined in `UIKit` bundle.
            return nil
        }

        guard !Bundle(for: type(of: viewController)).dd_isSwiftUI else {
            // `SwiftUI` requires manual instrumentation in views. Therefore, all SwiftUI
            // `UIKit` containers (e.g. `UIHostingController`) will be ignored from
            // auto-intrumentation.
            // This condition is wider and it ignores all view controllers defined in `SwiftUI` bundle.
            return nil
        }

        let canonicalClassName = viewController.canonicalClassName
        var view = RUMView(name: canonicalClassName)
        view.path = canonicalClassName
        return view
    }
}
