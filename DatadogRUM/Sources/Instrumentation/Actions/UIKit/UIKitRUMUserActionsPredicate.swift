/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import UIKit
import DatadogInternal

#if os(tvOS)
public typealias UIKitRUMActionsPredicate = UIPressRUMActionsPredicate
#else
public typealias UIKitRUMActionsPredicate = UITouchRUMActionsPredicate
#endif

/// The predicate for iOS interactions deciding if a given RUM Action should be recorded.
///
/// When the app is running, the SDK will ask the implementation of `UITouchRUMActionsPredicate` if any noticed user action on the target view should
/// be considered as a RUM Action. The predicate implementation should return RUM Action parameters if it should be recorded or `nil` otherwise.
public protocol UITouchRUMActionsPredicate {
    /// The predicate deciding if the RUM Action should be recorded.
    /// - Parameter targetView: an instance of the `UIView` which received the action.
    /// - Returns: RUM Action if it should be recorded, `nil` otherwise.
    func rumAction(targetView: UIView) -> RUMAction?
}

/// The predicate for tvOS interactions deciding if a given RUM Action should be recorded.
///
/// When the app is running, the SDK will ask the implementation of `UIPressRUMActionsPredicate` if any noticed user action on the target view should
/// be considered as a RUM Action. The predicate implementation should return RUM Action parameters if it should be recorded or `nil` otherwise.
public protocol UIPressRUMActionsPredicate {
    /// The predicate deciding if the RUM Action should be recorded.
    /// - Parameters:
    ///   - type: the `UIPress.PressType` which received the action.
    ///   - targetView: an instance of the `UIView` which received the action.
    /// - Returns: RUM Action if it should be recorded, `nil` otherwise.
    func rumAction(press type: UIPress.PressType, targetView: UIView) -> RUMAction?
}

/// Default implementation of `UIKitRUMActionsPredicate`.
/// It names  RUM Actions by the `accessibilityIdentifier` or `className` otherwise.
public struct DefaultUIKitRUMActionsPredicate {
    public init () {}

    /// Builds the RUM Action's `target` name for given `UIView`.
    private func targetName(for view: UIView) -> String {
        let className = NSStringFromClass(type(of: view))

        if let accessibilityIdentifier = view.accessibilityIdentifier {
            return "\(className)(\(accessibilityIdentifier))"
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
extension DefaultUIKitRUMActionsPredicate: UITouchRUMActionsPredicate {
    public func rumAction(targetView: UIView) -> RUMAction? {
        return RUMAction(
            name: targetName(for: targetView),
            attributes: [:]
        )
    }
}

// MARK: tvOS DefaultUIKitRUMActionsPredicate
extension DefaultUIKitRUMActionsPredicate: UIPressRUMActionsPredicate {
    public func rumAction(press type: UIPress.PressType, targetView: UIView) -> RUMAction? {
        var name: String

        switch type {
        case .select:
            name = targetName(for: targetView)
        case .menu:
            name = "menu"
        case .playPause:
            name = "play-pause"
        default:
            return nil
        }

        return RUMAction(name: name, attributes: [:])
    }
}

private extension UIView {
    var swiftUIViewName: String {
        if typeDescription.hasPrefix("ViewBasedUIButton") {
            return "SwiftUI_Menu"
        }

        return typeDescription
    }
}
#endif
