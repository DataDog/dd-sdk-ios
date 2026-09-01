/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(macOS)
import Foundation
import AppKit
import DatadogInternal
import os.log

internal struct MacOSSwiftUIComponentDetector: SwiftUIComponentDetector {
    typealias AccessibilityElement = AnyObject

    /// Used to make sure `setupAxClient()` runs only once.
    @MainActor private static var axSetupPerformed = false

    /// Creates an accessibility client for this application.
    ///
    /// The accessibility hierarchy will only be active if there is the application has a registered accessibility
    /// client. Clients like VoiceOver, or external hardware drivers, register themselves as accessibility clients,
    /// enabling the generation of accessibility hierarchies.
    ///
    /// Since SwiftUI instrumentation requires traversing the accessibility hierarchy, a client needs to be
    /// registered. In this case, the application is an accessibility client of itself.
    ///
    /// This method can be called multiple times safely.
    @MainActor
    private static func setupAxClient() {
        if axSetupPerformed == false {
            // Empirically, there is no need to keep `application` around after
            // creating it and setting the role below. As long as a client registers,
            // the accessibility machinery stays working even after the client
            // is gone.
            let application = AXUIElementCreateApplication(
                ProcessInfo.processInfo.processIdentifier
            )

            var role: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(
                application,
                kAXRoleAttribute as CFString,
                &role
            )

            if result == .success {
                axSetupPerformed = true
            } else {
                Logger().error("⚠️ Error initializing accessibility client for RUM SwiftUI instrumentation. RUM SwiftUI instrumentation may not work.")
            }
        }
    }

    /// Accessibility roles corresponding to interactive elements worth instrumenting.
    private static let interestingAccessibilityRoles: Set<String> = [
        kAXButtonRole,
        kAXRadioButtonRole,
        kAXCheckBoxRole,
        kAXPopUpButtonRole,
        kAXMenuButtonRole,
        kAXOutlineRole,
        kAXRowRole,
        kAXComboBoxRole,
        kAXSliderRole,
        kAXIncrementorRole,
        kAXTextFieldRole,
        kAXTextAreaRole,
        NSAccessibility.Role.link.rawValue
    ]

    @MainActor
    init() {
        Self.setupAxClient()
    }

    /// Creates a `RUMAddUserActionCommand` from an event based on the accessibility hierarchy.
    ///
    /// Since SwiftUI does not provide proper APIs to inspect the view hierarchy, the accessibility hierarchy is used to
    /// instrument SwiftUI view hierarchies.
    ///
    /// Read the documentation of `bestActionTargetFor(accessibilityElement:coordinates:)` and
    /// `traverseDownScrollViews(startingAt:coordinates:)` to understand more details of how the
    /// hierarchy is traversed to find the most appropriate interactive element for the given event.
    ///
    /// - Parameters:
    ///   - event: The event triggered by a user action.
    ///   - predicate: Predicate indicating if SwiftUI actions should be recorded.
    ///   - dateProvider: Provides dates for RUM events.
    ///
    /// - Returns: The command resulting from the given event, or `nil` if no action should be recorded for
    /// this event.
    func createActionCommand(from event: NSEvent, predicate: (any SwiftUIRUMActionsPredicate)?, dateProvider: any DatadogInternal.DateProvider) -> RUMAddUserActionCommand? {
        guard
            let predicate,
            let window = event.window,
            case let coordsInScreen = window.convertPoint(toScreen: event.locationInWindow),
            let accessibilityElement = axHitTesting(window, coordinates: coordsInScreen)
        else {
            return nil
        }

        guard let targetElement = bestActionTargetFor(accessibilityElement: accessibilityElement, coordinates: coordsInScreen) else {
            return nil
        }

        guard let action = predicate.rumAction(with: targetName(for: targetElement)) else {
            return nil
        }

        return RUMAddUserActionCommand(
            time: dateProvider.now,
            attributes: action.attributes,
            instrumentation: .swiftuiAutomatic,
            actionType: .click,
            name: action.name
        )
    }

    /// Builds the name of the accessibility target, based on its role and identifier.
    ///
    /// If identifier is defined, the name will be something like "AXButton (Checkout)". Otherwise, the name will
    /// only contain the role, as in "AXButton".
    ///
    /// - Parameters:
    ///   - accessibilityElement: The element to obtain the name from.
    ///
    /// - Returns: The name of the target represented by `accessibilityElement`.
    private func targetName(for accessibilityElement: AccessibilityElement) -> String {
        let roleString = accessibilityElement.accessibilityRole().map { $0.rawValue } ?? "<unknown>"
        if let identifier = axIdentifier(accessibilityElement), identifier.isEmpty == false {
            return "\(roleString) (\(identifier))"
        } else {
            return roleString
        }
    }

    /// Finds the interactive accessibility element in the given coordinates.
    ///
    /// Call this function with the result of `window.accessibilityHitTest` to further refine the result.
    ///
    /// If `accessibilityElement` is a scroll area, this method starts by traversing *down* the hierarchy looking for
    /// the first element that is not a scroll area. This supports nested scroll areas. After obtaining such element (or using
    /// `accessibilityElement` directly if it's not a scroll area), it traverses the hierarchy *up* looking for the first
    /// interactive element.
    ///
    /// - Parameters:
    ///   - accessibilityElement: The initial element returned by `window.accessibilityHitTest` for
    ///   the given coordinates.
    ///   - coordinates: The coordinates in the accessibility coordinate space.
    ///
    /// - Returns: The most appropriate interactive element as described above, or `nil` if no such element exists.
    private func bestActionTargetFor(accessibilityElement: AccessibilityElement, coordinates: NSPoint) -> AccessibilityElement? {
        var element: AccessibilityElement? = traverseDownScrollViews(startingAt: accessibilityElement, coordinates: coordinates)

        while let currentElement = element {
            if let role = axRole(currentElement),
               Self.interestingAccessibilityRoles.contains(role.rawValue) {
                return currentElement
            }

            element = axParent(currentElement)
        }

        return nil
    }

    /// If `accessibilityElement` is a scroll area (usually corresponding to a scroll view), it traverses the hierarchy
    /// *down* until it finds the first element that is not a scroll area.
    ///
    /// This method supports nested scroll views. For example, if the user clicked a button inside a scroll view that is, itself,
    /// inside another scroll view, this method traverses the hierarchy of both scroll views until it finds the button at the
    /// given coordinates.
    ///
    /// - Remark: Empirically, an accessibility element corresponding to a scroll view (with a `AXScrollArea` role)
    /// has, among its children, one of the type `AccessibilityLazyLayoutNode`. This node contains the actual
    /// accessibility contents of the scroll view. This method assumes that hierarchy, and will traverse the hierarchy looking
    /// for the `AccessibilityLazyLayoutNode` and performing a hit test on it to search for the next node. Since
    /// this is not formally documented by Apple, this method may break in future versions of macOS.
    ///
    /// - parameters:
    ///   - accessibilityElement: The accessibility element to start the search on.
    ///   - coordinates: The event coordinates in accessibility coordinate space.
    ///
    /// - returns: If `accessibilityElement` is not a scroll area, returns the element itself. Otherwise, it traverses
    /// the accessibility hierarchy down, as explained above, and returns the first element that is not a scroll area.
    private func traverseDownScrollViews(startingAt accessibilityElement: AccessibilityElement, coordinates: NSPoint) -> AccessibilityElement {
        func isScrollView(_ element: AccessibilityElement) -> Bool {
            // Should this be checking for AXScrollArea role?
            String(describing: type(of: element)).contains("HostingScrollView")
        }

        var currentElement = accessibilityElement

        while isScrollView(currentElement) {
            guard let children = currentElement.accessibilityChildren(),
                  let lazyNode = children.first(where: { node in
                      String(describing: type(of: node)).contains("AccessibilityLazyLayoutNode")
                  }) as? AccessibilityElement,
                  let newElement = axHitTesting(lazyNode, coordinates: coordinates)
            else {
                return currentElement
            }

            if newElement === currentElement || !isScrollView(newElement) {
                return newElement
            }

            currentElement = newElement
        }

        return currentElement
    }

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
    private func axRole(_ element: AccessibilityElement) -> NSAccessibility.Role? {
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
    private func axParent(_ element: AccessibilityElement) -> AccessibilityElement? {
        guard element.responds(to: #selector(NSAccessibilityProtocol.accessibilityParent)),
              let parent = element.accessibilityParent() as? AccessibilityElement
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
    private func axHitTesting(_ element: AccessibilityElement, coordinates: CGPoint) -> AccessibilityElement? {
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
    private func axIdentifier(_ element: AccessibilityElement) -> String? {
        guard element.responds(to: #selector(NSAccessibilityElementProtocol.accessibilityIdentifier)),
              let identifier = element.accessibilityIdentifier()
        else {
            return nil
        }

        return identifier
    }
}

#endif
