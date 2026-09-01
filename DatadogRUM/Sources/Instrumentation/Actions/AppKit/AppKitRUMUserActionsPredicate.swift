/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
import DatadogInternal

/// The predicate for macOS interactions deciding if a given RUM Action should be recorded.
///
/// When the app is running, the SDK will ask the implementation of `UITouchRUMActionsPredicate` if any noticed user action on the target view should
/// be considered as a RUM Action. The predicate implementation should return RUM Action parameters if it should be recorded or `nil` otherwise.
public protocol AppKitRUMActionsPredicate {
    /// The predicate deciding if the RUM Action should be recorded for a `.leftMouseDown` event on the given view.
    ///
    /// - Parameter targetView: an instance of the `NSView` which received the action.
    /// - Returns: RUM Action if it should be recorded, `nil` otherwise.
    func rumAction(targetView: NSView) -> RUMAction?

    /// The predicate deciding if the RUM Action should be recorded for the given menu item selected by the user.
    ///
    /// - Parameter targetMenuItem: A `NSMenuItem` selected by the user.
    /// - Returns: RUM Action if it should be recorded, `nil` otherwise.
    func rumAction(targetMenuItem: NSMenuItem) -> RUMAction?
}

/// Default implementation of `AppKitRUMActionsPredicate`.
/// It names  RUM Actions by the `accessibilityIdentifier` or `className` otherwise.
public struct DefaultAppKitRUMActionsPredicate {
    /// Name of the internal AppKit class used for the windows' zoom button.
    ///
    /// This is the green button of the usual "traffic-light" buttons on the left side of a window title bar.
    private static let WindowZoomButtonClassName = "_NSThemeZoomWidget"

    /// Name of the internal AppKit class used for the windows' minimize button.
    ///
    /// This is the yellow button of the usual "traffic-light" buttons on the left side of a window title bar.
    private static let WindowMinimizeButtonClassName = "_NSThemeWidget"

    /// Name of the internal AppKit class used for the windows' close button.
    ///
    /// This is the red button of the usual "traffic-light" buttons on the left side of a window title bar.
    private static let WindowCloseButtonClassName = "_NSThemeCloseWidget"

    public init () {}

    /// The name of the UI element which was the target of the action.
    ///
    /// If the view has its `accessibilityIdentifier` set, it will be included in the name. Otherwise, the name
    /// is generic (to protect privacy) based only on the view type.
    ///
    /// - Parameter view: The action target view.
    /// - Returns: The name of the target view to use in the RUM Action.
    private func targetName(for view: DDView) -> String {
        // In some situations, including when an interface is de-serialized from a XIB,
        // the accessibility identifier of some controls is associated to the control cell
        // instead. In other situations, like programmatically assigning an identifier to
        // a control, the identifier is only on the control. Therefore, in controls, both
        // are checked.
        let identifier: String? = {
            if let identifier = axIdentifier(view), identifier.isEmpty == false {
                return identifier
            }

            guard
                let control = view as? NSControl,
                let cell = control.cell
            else { return nil }

            if let cellIdentifier = axIdentifier(cell), cellIdentifier.isEmpty == false {
                return cellIdentifier
            }

            return nil
        }()

        if let identifier {
            return "\(baseName(for: view)) (\(identifier))"
        // Some SwiftUI components are UIKit under the hood,
        // but need to clean up tangled SwiftUI name
        // e.g., _TtCV7SwiftUIP33_D74FE142C3C5A6C2CEA4987A69AEBD7522SystemSegmentedControl18UISegmentedControl
        } else if view.isSwiftUIView {
            return view.swiftUIViewName
        } else {
            return baseName(for: view)
        }
    }

    /// The name of the `NSMenuItem` selected by the user..
    ///
    /// If the menu item has its `accessibilityIdentifier` set, it will be included in the name. Otherwise, the name
    /// is generic (to protect privacy) based only on the menu item class name, most often `NSMenuItem`.
    ///
    /// - Parameter menuItem: The menu item.
    /// - Returns: The name of the menu item to use in the RUM Action.
    private func targetName(for menuItem: NSMenuItem) -> String {
        let className = NSStringFromClass(type(of: menuItem))

        if menuItem.accessibilityIdentifier().isEmpty == false {
            return "\(className)(\(menuItem.accessibilityIdentifier()))"
        } else {
            return className
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
    ///
    /// - Parameter view: The view for which to extract the base name.
    /// - Returns: The base name of the view, as described above.
    private func baseName(for view: DDView) -> String {
        let baseName = NSStringFromClass(type(of: view))

        guard let button = view as? NSButton else {
            return baseName
        }

        // Detects clicks on the 3 traffic-light window buttons and adjusts
        // the name for something more user-friendly.
        switch baseName {
        case Self.WindowZoomButtonClassName: return "Window Zoom Button"
        case Self.WindowMinimizeButtonClassName: return "Window Minimize Button"
        case Self.WindowCloseButtonClassName: return "Window Close Button"
        default: break
        }

        // The kind is exposed as the cell's accessibility role (AppKit derives it from the
        // bezel + cell configuration). It must be read from the cell: NSButton itself reports
        // `.unknown`. Both disclosure styles (triangle and rounded) report `.disclosureTriangle`.
        if let role = (button.cell as? NSButtonCell)?.accessibilityRole() {
            if role == .checkBox {
                return "\(baseName) [checkbox]"
            }
            if role == .radioButton {
                return "\(baseName) [radio]"
            }
            if role == .disclosureTriangle {
                return "\(baseName) [disclosure]"
            }
        }

        // Help buttons report the generic `.button` role (same as push), so the bezel pins them down.
        // Note: macOS 14 renamed several cases (e.g. `.rounded` → `.push`,
        // `.roundedDisclosure` → `.pushDisclosure`); the legacy names still resolve.
        let bezel = button.bezelStyle
        if bezel == .helpButton {
            return "\(baseName) [help]"
        }
        if bezel == .roundedDisclosure {
            return "\(baseName) [disclosure]"
        }

        // Normal push button: regular, recessed, inline, gradient, textured, …
        return baseName
    }
}

// MARK: DefaultAppKitRUMActionsPredicate
extension DefaultAppKitRUMActionsPredicate: AppKitRUMActionsPredicate {
    public func rumAction(targetView: NSView) -> RUMAction? {
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
