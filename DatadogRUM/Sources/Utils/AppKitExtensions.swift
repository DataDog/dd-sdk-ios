/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(AppKit)
import AppKit

internal extension NSWindow {
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
#endif
