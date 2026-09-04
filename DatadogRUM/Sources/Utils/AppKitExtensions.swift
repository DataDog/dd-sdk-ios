/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(AppKit)
import AppKit

internal extension NSWindow {
    /// Obtains the window's root view.
    ///
    /// This is an internal view that has, as child views, both the content view and the toolbar view.
    var rootView: NSView? {
        var rootView = contentView

        while let superview = rootView?.superview {
            rootView = superview
        }

        return rootView
    }
}

internal extension NSMenuItem {
    /// `true` is tracking this Menu Item does not present a privacy issue, `false` otherwise.
    var isSafeForPrivacy: Bool {
        // No default menu item is inherently unsafe, so consider all safe for now.
        true
    }
}

internal extension NSView {
    /// `true` if this view is an instance of `NSToolbarItemViewer` or a subclass of it, `false` otherwise.
    var isNSToolbarItemViewer: Bool {
        guard let toolbarItemViewerClass else {
            return false
        }

        return isKind(of: toolbarItemViewerClass)
    }
}

/// Obtains the Class object for the AppKit internal `NSToolbarItemViewer` class.
internal var toolbarItemViewerClass: AnyClass? = {
    NSClassFromString("NSToolbarItemViewer")
}()

#endif
