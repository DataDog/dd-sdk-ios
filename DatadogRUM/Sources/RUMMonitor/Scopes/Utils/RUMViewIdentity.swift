/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

/// A type providing stable identity for a RUM View.
/// Based on the `equals(_:)` implementation, it decides if two `RUMViewIdentifiables` identify the same
/// RUM View or not. Each implementation of the `RUMViewIdentifiable` decides by its own if it should use
/// reference or value semantic for the comparison.
fileprivate protocol RUMViewIdentifiable {
    /// Compares the instance of this identifiable with another `RUMViewIdentifiable`.
    /// It returns `true` if both identify the same RUM View and `false` otherwise.
    func equals(_ otherIdentifiable: RUMViewIdentifiable?) -> Bool

    /// Converts the instance of this type to `RUMViewIdentity`.
    func asRUMViewIdentity() -> RUMViewIdentity

    /// If the RUM View's path name is not given explicitly by the user, each implementation of the `RUMViewIdentifiable`
    /// must return a default path name.
    var defaultViewPath: String { get }
}

// MARK: - Supported `RUMViewIdentifiables`

/// Extends `UIViewController` with the ability to identify the RUM View.
extension UIViewController: RUMViewIdentifiable {
    fileprivate func equals(_ otherIdentifiable: RUMViewIdentifiable?) -> Bool {
        if let otherViewController = otherIdentifiable as? UIViewController {
            // Two `UIViewController` identifiables indicate the same RUM View only if their references are equal.
            return self === otherViewController
        } else {
            return false
        }
    }

    func asRUMViewIdentity() -> RUMViewIdentity {
        return RUMViewIdentity(object: self)
    }

    var defaultViewPath: String {
        return canonicalClassName
    }
}

/// Extends `String` with the ability to identify the RUM View.
extension String: RUMViewIdentifiable {
    fileprivate func equals(_ otherIdentifiable: RUMViewIdentifiable?) -> Bool {
        if let otherString = otherIdentifiable as? String {
            // Two `String` identifiables indicate the same RUM View only if their values are equal.
            return self == otherString
        } else {
            return false
        }
    }

    func asRUMViewIdentity() -> RUMViewIdentity {
        return RUMViewIdentity(value: self)
    }

    var defaultViewPath: String { self }
}

// MARK: - `RUMViewIdentity`

/// Manages the `RUMViewIdentifiable` by using either reference or value semantic.
internal struct RUMViewIdentity {
    private weak var object: AnyObject?
    private let value: Any?

    /// Initializes the `RUMViewIdentity` using reference semantic.
    /// A weak reference to given `object` is stored internally.
    fileprivate init(object: RUMViewIdentifiable) {
        self.object = object as AnyObject
        self.value = nil
    }

    /// Initializes the `RUMViewIdentity` using value semantic.
    /// A copy of the given `value` is stored internally.
    fileprivate init(value: RUMViewIdentifiable) {
        self.object = nil
        self.value = value
    }

    /// Returns `true` if a given identifiable indicates the same RUM View as the identifiable managed internally.
    fileprivate func equals(_ identifiable: RUMViewIdentifiable?) -> Bool {
        return self.identifiable?.equals(identifiable) ?? false
    }

    /// Returns `true` if a given identity indicates the same RUM View as the identifiable managed internally.
    func equals(_ identity: RUMViewIdentity?) -> Bool {
        return equals(identity?.identifiable)
    }

    /// Return default path name for the managed identifiable.
    var defaultViewPath: String {
        return identifiable?.defaultViewPath ?? ""
    }

    /// Returns `true` if the managed identifiable is still available.
    /// Underlying `identfiable` is stored as a weak reference, so it may become `nil` at any time.
    /// For example when the `UIViewController` is deallocated.
    var exists: Bool {
        return identifiable != nil
    }

    /// Returns the managed identifiable.
    private var identifiable: RUMViewIdentifiable? {
        return (object as? RUMViewIdentifiable) ?? (value as? RUMViewIdentifiable)
    }
}
