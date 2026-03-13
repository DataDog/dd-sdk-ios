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
        let className = NSStringFromClass(type(of: view))

        if view.accessibilityIdentifier().isEmpty == false {
            return "\(className)(\(view.accessibilityIdentifier()))"
        } else if let button = view as? NSButton, button.title.isEmpty == false {
            return button.title
        } else if let control = view as? NSControl {
            return className + (control.action.map { " \($0.description)" } ?? "")
        // Some SwiftUI components are UIKit under the hood,
        // but need to clean up tangled SwiftUI name
        // e.g., _TtCV7SwiftUIP33_D74FE142C3C5A6C2CEA4987A69AEBD7522SystemSegmentedControl18UISegmentedControl
        } else if view.isSwiftUIView {
            return view.swiftUIViewName
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
            name: "'\(targetMenuItem.title)' Menu Item",
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
