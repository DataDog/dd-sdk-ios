/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(AppKit)
import AppKit

internal typealias AccessibilityElement = AnyObject

/// Obtains the accessibility role of a given accessibility element.
///
/// - Note: Given how the informal accessibility protocols work, the only fully reliable way to safely call the
/// `accessibilityRole()` on a given object and avoid a crash is by making sure the object responds
/// to that selector. This method wraps that complexity.
///
/// - Parameters:
///   - element: The accessibility element the caller wants the role of.
///
/// - returns: The accessibility role of the given element, or `nil` if the given element has no role, or
/// does not respond to `accessibilityRole()`.
internal func axRole(_ element: AccessibilityElement) -> NSAccessibility.Role? {
    guard element.responds(to: #selector(NSAccessibilityProtocol.accessibilityRole)),
          let role = element.accessibilityRole()
    else {
        return nil
    }

    return role
}

/// Obtains the accessibility parent of a given accessibility element.
///
/// - Note: Given how the informal accessibility protocols work, the only fully reliable way to safely call the
/// `accessibilityParent()` method on a given object and avoid a crash is by making sure the object responds
/// to that selector. This method wraps that complexity.
///
/// - Parameters:
///   - element: The accessibility element the caller wants the parent of.
///
/// - returns: The accessibility parent of the given element, or `nil` if the given element has no parent, or
/// does not respond to `accessibilityParent()`.
internal func axParent(_ element: AccessibilityElement) -> AccessibilityElement? {
    guard element.responds(to: #selector(NSAccessibilityProtocol.accessibilityParent)),
          let parent = element.accessibilityParent() as? AccessibilityElement
    else {
        return nil
    }

    return parent
}

/// Obtains the accessibility children of a given accessibility element.
///
/// - Note: Given how the informal accessibility protocols work, the only fully reliable way to safely call the
/// `accessibilityChildren()` method on a given object and avoid a crash is by making sure the object responds
/// to that selector. This method wraps that complexity.
///
/// - Parameters:
///   - element: The accessibility element the caller wants the children of.
///
/// - returns: The accessibility children of the given element, or `nil` if the given element does not respond to
/// `accessibilityChildren()`.
internal func axChildren(_ element: AccessibilityElement) -> [Any]? {
    guard element.responds(to: #selector(NSAccessibilityProtocol.accessibilityChildren)),
          let parent = element.accessibilityChildren()
    else {
        return nil
    }

    return parent
}

/// Obtains the result of calling `accessibilityHitTest` for the given coordinates on the given element.
///
/// - Note: Given how the informal accessibility protocols work, the only fully reliable way to safely call the
/// `accessibilityHitTest(coords:)` method on a given object and avoid a crash is by making sure the object
/// responds to that selector. This method wraps that complexity.
///
/// - Parameters:
///   - element: The accessibility element the caller wants to call `accessibilityHitTest` on.
///   - coordinates: The coordinates to test, in the accessibility coordinate space.
///
/// - returns: The result of calling `accessibilityHitTest` on the given element with the given
/// coordinates, or `nil` if `element` does not consider `coordinates` to be inside itself, or does not
/// respond to `accessibilityHitTest(coords:)`.
internal func axHitTesting(_ element: AccessibilityElement, coordinates: CGPoint) -> AccessibilityElement? {
    guard element.responds(to: #selector(NSObject.accessibilityHitTest)),
          let element = element.accessibilityHitTest(coordinates) as? AccessibilityElement
    else {
        return nil
    }

    return element
}

/// Obtains the accessibility identifier of a given element.
///
/// - Note: Given how the informal accessibility protocols work, the only fully reliable way to safely call the
/// `accessibilityIdentifier()` method on a given object and avoid a crash is by making sure the object
/// responds to that selector. This method wraps that complexity.
///
/// - Parameters:
///   - element: The accessibility element the caller wants to call `accessibilityIdentifier` on.
///
/// - returns: The element's accessibility identifier, or `nil` if it does not have an accessibility identifier.
internal func axIdentifier(_ element: AccessibilityElement) -> String? {
    guard element.responds(to: #selector(NSAccessibilityElementProtocol.accessibilityIdentifier)),
          let identifier = element.accessibilityIdentifier()
    else {
        return nil
    }

    return identifier
}

/// `true` if the accessibility element responds to user events, `false` otherwise.
///
/// - Note: Given how the informal accessibility protocols work, the only fully reliable way to safely call the
/// `isAccessibilityEnabled()` method on a given object and avoid a crash is by making sure the object
/// responds to that selector. This method wraps that complexity.
///
/// - Parameters:
///   - element: The accessibility element the caller wants to call `isAccessibilityEnabled()` on.
///
/// - returns: A boolean indicating if the accessibility element responds to user events, or `nil` if it does
/// not respond to `isAccessibilityEnabled()`.
internal func axIsEnabled(_ element: AccessibilityElement) -> Bool? {
    guard element.responds(to: #selector(NSAccessibilityProtocol.isAccessibilityEnabled)) else {
        return nil
    }

    return element.isAccessibilityEnabled()
}

#endif
