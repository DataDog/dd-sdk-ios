/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

/// A description of the RUM View returned from the `UIKitRUMViewsPredicate`.
public struct RUMView {
    /// The RUM View name, appearing as `VIEW NAME` in RUM Explorer.
    public var name: String

    /// The RUM View path, appearing as `VIEW PATH GROUP` / `VIEW URL` in RUM Explorer.
    /// If set `nil`, the view controller class name will be used.
    public var path: String?

    /// Additional attributes to associate with the RUM View.
    public var attributes: [AttributeKey: AttributeValue]

    /// Initializes the RUM View description.
    /// - Parameters:
    ///   - path: the RUM View path, appearing as `PATH` in RUM Explorer.
    ///   - attributes: additional attributes to associate with the RUM View.
    @available(*, deprecated, message: "This initializer is renamed to `init(name:attributes:)`.")
    public init(path: String, attributes: [AttributeKey: AttributeValue] = [:]) {
        self.name = path
        self.path = path
        self.attributes = attributes
    }

    /// Initializes the RUM View description.
    /// - Parameters:
    ///   - name: the RUM View name, appearing as `VIEW NAME` in RUM Explorer.
    ///   - attributes: additional attributes to associate with the RUM View.
    public init(name: String, attributes: [AttributeKey: AttributeValue] = [:]) {
        self.name = name
        self.path = nil // the "VIEW URL" will default to view controller class name
        self.attributes = attributes
    }
}

/// The predicate deciding if a given `UIViewController` indicates the RUM View.
///
/// When the app is running, the SDK will ask the implementation of `UIKitRUMViewsPredicate` if any noticed `UIViewController` should be considered
/// as the RUM View. The predicate implementation should return RUM View parameters if the `UIViewController` should start/end
/// the RUM View or `nil` otherwise.
public protocol UIKitRUMViewsPredicate {
    /// The predicate deciding if the RUM View should be started or ended for given instance of the `UIViewController`.
    /// - Parameter viewController: an instance of the view controller noticed by the SDK.
    /// - Returns: RUM View parameters if received view controller should start/end the RUM View, `nil` otherwise.
    func rumView(for viewController: UIViewController) -> RUMView?
}

/// Default implementation of `UIKitRUMViewsPredicate`.
/// It names  RUM Views by the names of their `UIViewController` subclasses.
public struct DefaultUIKitRUMViewsPredicate: UIKitRUMViewsPredicate {
    public init () {}

    public func rumView(for viewController: UIViewController) -> RUMView? {
        guard !isUIKit(class: type(of: viewController)) else {
            // Part of our heuristic for (auto) tracking view controllers is to ignore
            // container view controllers coming from `UIKit` if they are not subclassed.
            // This condition is wider and it ignores all view controllers defined in `UIKit` bundle.
            return nil
        }

        let canonicalClassName = viewController.canonicalClassName
        var view = RUMView(name: canonicalClassName)
        view.path = canonicalClassName
        return view
    }

    /// If given `class` comes from UIKit framework.
    private func isUIKit(`class`: AnyClass) -> Bool {
        return Bundle(for: `class`).isUIKit
    }
}
