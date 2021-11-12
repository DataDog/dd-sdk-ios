/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2021 Datadog, Inc.
 */

import UIKit

/// A description of the RUM Action returned from the `UIKitRUMUserActionsPredicate`.
public struct RUMAction {
    /// The RUM Action name, appearing as `ACTION NAME` in RUM Explorer. If no name is given, default one will be used.
    public var name: String

    /// Additional attributes to associate with the RUM Action.
    public var attributes: [AttributeKey: AttributeValue]

    /// Initializes the RUM Action description.
    /// - Parameters:
    ///   - name: the RUM Action name, appearing as `Action NAME` in RUM Explorer. If no name is given, default one will be used.
    ///   - attributes: additional attributes to associate with the RUM Action.
    public init(name: String, attributes: [AttributeKey: AttributeValue] = [:]) {
        self.name = name
        self.attributes = attributes
    }
}

/// The predicate deciding if a given RUM Action should be recorded.
///
/// When the app is running, the SDK will ask the implementation of `UIKitRUMUserActionsPredicate` if any noticed user action on the target view should
/// be considered as the RUM Action. The predicate implementation should return RUM Action parameters if it should be recorded or `nil` otherwise.
public protocol UIKitRUMUserActionsPredicate {
    /// The predicate deciding if the RUM Action should be recorded.
    /// - Parameter targetView: an instance of the `UIView` which received the action.
    /// - Returns: RUM Action if it should be recorded, `nil` otherwise.
    func rumAction(targetView: UIView) -> RUMAction?
}

/// Default implementation of `UIKitRUMUserActionsPredicate`.
/// It names  RUM Actions by the `accessibilityIdentifier` or `className` otherwise.
public struct DefaultUIKitRUMUserActionsPredicate: UIKitRUMUserActionsPredicate {
    public init () {}

    public func rumAction(targetView: UIView) -> RUMAction? {
        return RUMAction(
            name: targetName(for: targetView),
            attributes: [:]
        )
    }

    /// Builds the RUM Action's `target` name for given `UIView`.
    private func targetName(for view: UIView) -> String {
        let className = NSStringFromClass(type(of: view))

        if let accessibilityIdentifier = view.accessibilityIdentifier {
            return "\(className)(\(accessibilityIdentifier))"
        } else {
            return className
        }
    }
}
