/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(AppKit)
import AppKit
import DatadogInternal

public typealias UIKitRUMActionsPredicate = AppKitRUMActionsPredicate

/// The predicate for macOS interactions deciding if a given RUM Action should be recorded.
///
/// When the app is running, the SDK will ask the implementation of `UITouchRUMActionsPredicate` if any noticed user action on the target view should
/// be considered as a RUM Action. The predicate implementation should return RUM Action parameters if it should be recorded or `nil` otherwise.
public protocol AppKitRUMActionsPredicate {
    /// The predicate deciding if the RUM Action should be recorded.
    /// - Parameter targetView: an instance of the `UIView` which received the action.
    /// - Returns: RUM Action if it should be recorded, `nil` otherwise.
    func rumAction(targetView: DDView) -> RUMAction?

    func rumAction(targetMenuItem: NSMenuItem) -> RUMAction?
}

/// Default implementation of `UIKitRUMActionsPredicate`.
/// It names  RUM Actions by the `accessibilityIdentifier` or `className` otherwise.
public struct DefaultAppKitRUMActionsPredicate {
    public init () {}

    /// Builds the RUM Action's `target` name for given `DDView`.
    private func targetName(for view: DDView) -> String {
        if view.accessibilityIdentifier().isEmpty == false {
            return "\(baseName(for: view)) (\(view.accessibilityIdentifier()))"
        // Some SwiftUI components are UIKit under the hood,
        // but need to clean up tangled SwiftUI name
        // e.g., _TtCV7SwiftUIP33_D74FE142C3C5A6C2CEA4987A69AEBD7522SystemSegmentedControl18UISegmentedControl
        } else if view.isSwiftUIView {
            return view.swiftUIViewName
        } else {
            return baseName(for: view)
        }
    }

    /// Maps an `NSButton` to a synthetic base name describing its *kind*.
    ///
    /// AppKit has no readable "button type": the kind (push / checkbox / radio / disclosure / help)
    /// is the combined result of bezel style, cell configuration, images, etc. Rather than reverse
    /// engineer that combination, we read back the value AppKit already derives from it — the
    /// accessibility role — which cleanly separates checkbox, radio and the disclosure triangle.
    /// The remaining kinds all report the generic `.button` role, so we disambiguate those few
    /// with the bezel style.
    private func baseName(for view: DDView) -> String {
        let baseName = NSStringFromClass(type(of: view))

        guard let button = view as? NSButton else {
            return baseName
        }

        // The kind is exposed as the cell's accessibility role (AppKit derives it from the
        // bezel + cell configuration). It must be read from the cell: NSButton itself reports
        // `.unknown`. Both disclosure styles (triangle and rounded) report `.disclosureTriangle`.
        if let role = (button.cell as? NSButtonCell)?.accessibilityRole() {
            if role == .checkBox { return "\(baseName) [checkbox]" }
            if role == .radioButton { return "\(baseName) [radio]" }
            if role == .disclosureTriangle { return "\(baseName) [disclosure]" }
        }

        // Help buttons report the generic `.button` role (same as push), so the bezel pins them down.
        // Note: macOS 14 renamed several cases (e.g. `.rounded` → `.push`,
        // `.roundedDisclosure` → `.pushDisclosure`); the legacy names still resolve.
        let bezel = button.bezelStyle
        if bezel == .helpButton { return "\(baseName) [help]" }
        if bezel == .roundedDisclosure { return "\(baseName) [disclosure]" }

        // Normal push button: regular, recessed, inline, gradient, textured, …
        return baseName
    }

    private func targetName(for menuItem: NSMenuItem) -> String {
        let className = NSStringFromClass(type(of: menuItem))

        if menuItem.accessibilityIdentifier().isEmpty == false {
            return "\(className)(\(menuItem.accessibilityIdentifier()))"
        // Some SwiftUI components are UIKit under the hood,
        // but need to clean up tangled SwiftUI name
        // e.g., _TtCV7SwiftUIP33_D74FE142C3C5A6C2CEA4987A69AEBD7522SystemSegmentedControl18UISegmentedControl
        } else {
            return className
        }
    }
}

// MARK: iOS DefaultUIKitRUMActionsPredicate
extension DefaultAppKitRUMActionsPredicate: AppKitRUMActionsPredicate {
    public func rumAction(targetView: DDView) -> RUMAction? {
        return RUMAction(
            name: targetName(for: targetView),
            attributes: [:]
        )
    }

    public func rumAction(targetMenuItem: NSMenuItem) -> RUMAction? {
        return RUMAction(
            name: targetName(for: targetMenuItem),
            attributes: [:]
        )
    }
}

private extension DDView {
    var swiftUIViewName: String {
        if typeDescription.hasPrefix("ViewBasedUIButton") {
            return "SwiftUI_Menu"
        }

        return typeDescription
    }
}
#endif
