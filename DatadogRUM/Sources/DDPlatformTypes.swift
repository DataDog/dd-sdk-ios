/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

/// Platform-agnostic type aliases bridging UIKit (iOS / tvOS / visionOS) and AppKit (macOS).
///
/// Use these aliases throughout DatadogRUM to avoid `#if canImport(UIKit)` scatter in
/// implementation files. Types with no meaningful AppKit equivalent (e.g. `UIAccessibility`,
/// `UIContentSizeCategory`, `UIPress`, `UIDevice`) are intentionally excluded and must be
/// guarded at the call site with `#if canImport(UIKit)`.

#if canImport(UIKit)
import UIKit

// MARK: - Views
public typealias DDView = UIView
public typealias DDControl = UIControl
public typealias DDLabel = UILabel
public typealias DDButton = UIButton
public typealias DDScrollView = UIScrollView
public typealias DDStackView = UIStackView
public typealias DDSegmentedControl = UISegmentedControl
public typealias DDWindow = UIWindow
public typealias DDScreen = UIScreen

// MARK: - View Controllers
public typealias DDViewController = UIViewController
public typealias DDNavigationController = UINavigationController
public typealias DDTabBarController = UITabBarController

// MARK: - Application
public typealias DDApplication = UIApplication

// MARK: - Events
public typealias DDEvent = UIEvent
public typealias DDTouch = UITouch

// MARK: - Appearance
public typealias DDColor = UIColor
public typealias DDFont = UIFont

// MARK: - Collection / Table Cells
public typealias DDTableViewCell = UITableViewCell
public typealias DDCollectionViewCell = UICollectionViewCell

#elseif canImport(AppKit)
import AppKit

// MARK: - Views
public typealias DDView = NSView
public typealias DDControl = NSControl
/// Closest AppKit equivalent; configure with `isEditable = false` / `isBezeled = false` for label behaviour.
public typealias DDLabel = NSTextField
public typealias DDButton = NSButton
public typealias DDScrollView = NSScrollView
public typealias DDStackView = NSStackView
public typealias DDSegmentedControl = NSSegmentedControl
public typealias DDWindow = NSWindow
public typealias DDScreen = NSScreen

// MARK: - View Controllers
public typealias DDViewController = NSViewController
/// No direct AppKit equivalent — aliased to `NSViewController` for compilation purposes.
public typealias DDNavigationController = NSViewController
/// No direct AppKit equivalent — aliased to `NSViewController` for compilation purposes.
public typealias DDTabBarController = NSViewController

// MARK: - Application
public typealias DDApplication = NSApplication

// MARK: - Events
/// `NSEvent` covers all input events on macOS (mouse, keyboard, scroll, etc.).
public typealias DDEvent = NSEvent
/// `NSTouch` represents trackpad touches on macOS; semantically different from `UITouch`.
public typealias DDTouch = NSTouch

// MARK: - Appearance
public typealias DDColor = NSColor
public typealias DDFont = NSFont

// MARK: - Collection / Table Cells
/// Closest AppKit equivalent to `UITableViewCell` — an `NSView`-based cell.
public typealias DDTableViewCell = NSTableCellView
/// `NSCollectionViewItem` is the AppKit equivalent; note it is an `NSViewController` subclass.
public typealias DDCollectionViewCell = NSCollectionViewItem

// MARK: - Application lifecycle notifications
/// Maps `UIApplication.didEnterBackgroundNotification` → `NSApplication.didResignActiveNotification`.
extension NSApplication {
    static var didEnterBackgroundNotification: Notification.Name { NSApplication.didResignActiveNotification }
    static var willEnterForegroundNotification: Notification.Name { NSApplication.didBecomeActiveNotification }
}

#endif
