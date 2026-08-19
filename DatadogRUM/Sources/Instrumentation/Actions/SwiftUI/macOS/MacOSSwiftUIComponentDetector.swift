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

struct MacOSSwiftUIComponentDetector: SwiftUIComponentDetector {

    typealias AccessibilityElement = AnyObject

    @MainActor
    private static var axSetupPerformed = false

    @MainActor
    private static func setupAxClient() {
        if axSetupPerformed == false {
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
        kAXTextAreaRole
    ]

    @MainActor
    init() {
        Self.setupAxClient()
    }

    func createActionCommand(from event: NSEvent, predicate: (any SwiftUIRUMActionsPredicate)?, dateProvider: any DatadogInternal.DateProvider) -> RUMAddUserActionCommand? {

        guard
            let window = event.window,
            let screen = window.screen,
            case let coordsInScreen = window.convertPoint(toScreen: event.locationInWindow),
            let accessibilityElement = axHitTesting(window, coordinates: coordsInScreen) as? AccessibilityElement
        else {
            return nil
        }

        //print(accessibilityElement.accessibilityRole())
        //print(accessibilityElement.accessibilityRoleDescription())

        guard let targetElement = bestActionTargetFor(accessibilityElement: accessibilityElement, window: window, coordinates: coordsInScreen) else {
            print("targetElement returned nope")
            return nil
        }

        guard let action = predicate?.rumAction(with: targetName(for: targetElement)) else {
            return nil
        }

        return RUMAddUserActionCommand(
            time: dateProvider.now,
            attributes: action.attributes,
            instrumentation: .appKit,
            actionType: .click,
            name: action.name
        )
    }

    private func targetName(for accessibilityElement: AccessibilityElement) -> String {
        let roleString = accessibilityElement.accessibilityRole().map { $0.rawValue } ?? "<unknown>"
        if let identifier = accessibilityElement.accessibilityIdentifier(), identifier.isEmpty == false {
            return "\(roleString) (\(identifier))"
        } else {
            return roleString
        }
    }

    private func bestActionTargetFor(accessibilityElement: AccessibilityElement, window: NSWindow, coordinates: NSPoint) -> AccessibilityElement? {

        var element: AccessibilityElement? = traverseDownScrollViews(startingAt: accessibilityElement, window: window, coordinates: coordinates)

        while let currentElement = element {
            if let role = axRole(currentElement),
               Self.interestingAccessibilityRoles.contains(role.rawValue) {
                return currentElement
            }

            element = axParent(currentElement)
        }

        return nil
    }

    private func traverseDownScrollViews(startingAt accessibilityElement: AccessibilityElement, window: NSWindow, coordinates: NSPoint) -> AccessibilityElement {

        func isScrollView(_ element: AccessibilityElement) -> Bool {
            String(describing: type(of: element)).contains("HostingScrollView")
        }

        var currentElement = accessibilityElement

        while isScrollView(currentElement) {
            guard let children = currentElement.accessibilityChildren(),
                  let lazyNode = children.first(where: { node in
                      String(describing: type(of: node)).contains("AccessibilityLazyLayoutNode")
                  }) as? AccessibilityElement,
                  let newElement = axHitTesting(lazyNode, coordinates: coordinates) as? AccessibilityElement
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

    private func axRole(_ element: AccessibilityElement) -> NSAccessibility.Role? {
        guard element.responds(to: #selector(NSAccessibilityProtocol.accessibilityRole)),
              let role = element.accessibilityRole()
        else {
            return nil
        }

        return role
    }

    private func axParent(_ element: AccessibilityElement) -> AccessibilityElement? {
        guard element.responds(to: #selector(NSAccessibilityProtocol.accessibilityParent)),
              let parent = element.accessibilityParent() as? AccessibilityElement
        else {
            return nil
        }

        return parent
    }

    private func axHitTesting(_ element: AccessibilityElement, coordinates: CGPoint) -> AccessibilityElement? {
        guard element.responds(to: #selector(NSObject.accessibilityHitTest)),
              let element = element.accessibilityHitTest(coordinates) as? AccessibilityElement
        else {
            return nil
        }

        return element
    }
}

#endif
