/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

/// A description of the RUM View returned from the `UIKitRUMViewsPredicate`.
public struct RUMViewFromPredicate {
    // TODO: RUMM-726 Rename to `RUMView` when this name is no longer taken by auto-generated model(s).

    /// The RUM View path, appearing as `PATH` in RUM Explorer.
    public var path: String

    /// Additional attributes to associate with the RUM View.
    public var attributes: [AttributeKey: AttributeValue]

    /// Initializes the RUM View description.
    /// - Parameters:
    ///   - path: the RUM View path, appearing as "PATH" in RUM Explorer.
    ///   - attributes: additional attributes to associate with the RUM View.
    public init(path: String, attributes: [AttributeKey: AttributeValue] = [:]) {
        self.path = path
        self.attributes = attributes
    }
}

/// The predicate deciding if a given `UIViewController` marks the beginning or end of the RUM View.
///
/// When the app is running, the SDK will ask the implementation of `UIKitRUMViewsPredicate` if any noticed `UIViewController` should be considered
/// as the RUM View. The predicate implementation should return RUM View parameters if the `UIViewController` should start/end
/// the RUM View or `nil` otherwise.
public protocol UIKitRUMViewsPredicate {
    /// The predicate deciding if the RUM View should be started or ended for given instance of the `UIViewController`.
    /// - Parameter viewController: an instance of the view controller noticed by the SDK.
    /// - Returns: RUM View parameters if received view controller should start/end the RUM View, `nil` otherwise.
    func rumView(for viewController: UIViewController) -> RUMViewFromPredicate?
}
