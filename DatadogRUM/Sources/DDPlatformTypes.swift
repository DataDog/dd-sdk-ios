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
#if !os(watchOS)

// MARK: - Application
internal typealias DDApplication = UIApplication

// MARK: - Views
internal typealias DDView = UIView
internal typealias DDControl = UIControl
internal typealias DDLabel = UILabel
internal typealias DDButton = UIButton
internal typealias DDScrollView = UIScrollView
internal typealias DDStackView = UIStackView
internal typealias DDSegmentedControl = UISegmentedControl
internal typealias DDWindow = UIWindow
#if !os(visionOS)
internal typealias DDScreen = UIScreen
#endif

// MARK: - View Controllers
internal typealias DDViewController = UIViewController

// MARK: - Events
internal typealias DDEvent = UIEvent
internal typealias DDTouch = UITouch

// MARK: - Collection / Table Cells
internal typealias DDTableViewCell = UITableViewCell
internal typealias DDCollectionViewCell = UICollectionViewCell

// MARK: - Accessibility
internal typealias DDAccessibility = UIAccessibility

internal typealias DDKitRUMActionsPredicate = UIKitRUMActionsPredicate
internal typealias DDKitRUMViewsPredicate = UIKitRUMViewsPredicate
#endif

// MARK: - Appearance
internal typealias DDColor = UIColor
internal typealias DDFont = UIFont

#if canImport(SwiftUI) && (os(iOS) || os(tvOS) || os(visionOS))
import SwiftUI

@available(iOS 13.0, tvOS 13.0, *)
internal typealias DDHostingController = UIHostingController
#endif

#elseif canImport(AppKit)
import AppKit

// MARK: - Application
internal typealias DDApplication = NSApplication

// MARK: - Views
internal typealias DDView = NSView
internal typealias DDControl = NSControl
/// Closest AppKit equivalent; configure with `isEditable = false` / `isBezeled = false` for label behaviour.
internal typealias DDLabel = NSTextField
internal typealias DDButton = NSButton
internal typealias DDScrollView = NSScrollView
internal typealias DDStackView = NSStackView
internal typealias DDSegmentedControl = NSSegmentedControl
internal typealias DDWindow = NSWindow
internal typealias DDScreen = NSScreen

// MARK: - View Controllers
internal typealias DDViewController = NSViewController

// MARK: - Events
/// `NSEvent` covers all input events on macOS (mouse, keyboard, scroll, etc.).
internal typealias DDEvent = NSEvent
/// `NSTouch` represents trackpad touches on macOS; semantically different from `UITouch`.
internal typealias DDTouch = NSTouch

// MARK: - Appearance
internal typealias DDColor = NSColor
internal typealias DDFont = NSFont

// MARK: - Collection / Table Cells
/// Closest AppKit equivalent to `UITableViewCell` — an `NSView`-based cell.
internal typealias DDTableViewCell = NSTableCellView
/// `NSCollectionViewItem` is the AppKit equivalent; note it is an `NSViewController` subclass.
internal typealias DDCollectionViewCell = NSCollectionViewItem

// MARK: - Accessibility
/// Stub namespace matching `UIAccessibility` API surface used in DatadogRUM.
/// AppKit exposes accessibility via `NSAccessibility` (a protocol) and top-level functions;
/// this enum provides a compilation target — actual macOS values are not supported.
internal typealias DDAccessibility = NSAccessibility

// MARK: - Application lifecycle notifications
/// Maps `UIApplication.didEnterBackgroundNotification` → `NSApplication.didResignActiveNotification`.
extension NSApplication {
    static var didEnterBackgroundNotification: Notification.Name { NSApplication.didResignActiveNotification }
    static var willEnterForegroundNotification: Notification.Name { NSApplication.didBecomeActiveNotification }
}

// MARK: - SDK specific
internal typealias DDKitRUMActionsPredicate = MacOSRUMActionsPredicate
internal typealias DDKitRUMViewsPredicate = AppKitRUMViewsPredicate

#if canImport(SwiftUI)
import SwiftUI

internal typealias DDHostingController = NSHostingController
#endif

#endif
