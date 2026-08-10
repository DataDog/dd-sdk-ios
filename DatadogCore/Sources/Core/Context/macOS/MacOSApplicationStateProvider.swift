/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(macOS)

import AppKit

/// Provides information required to calculate `AppStatus` coming from macOS APIs.
///
/// This exists as a separate entity so we can inject a different implementation during testing.
internal protocol MacOSApplicationStateProvider {
    /// `true` if the application is active, `false` otherwise.
    var isActive: Bool { get }

    /// `true` if all the windows applications are hidden, `false` otherwise.
    var isHidden: Bool { get }

    /// `true` is the login window is the active, frontmost process, `false` otherwise.
    var frontmostApplicationIsLoginWindow: Bool { get }
}

/// Default implementation of `MacOSApplicationStateProvider`.
internal struct DefaultMacOSApplicationStateProvider: MacOSApplicationStateProvider {
    var isActive: Bool {
        NSApplication.shared.isActive
    }

    var isHidden: Bool {
        NSApplication.shared.isHidden
    }

    var frontmostApplicationIsLoginWindow: Bool {
        NSWorkspace.shared.frontmostApplicationIsLoginWindow
    }
}

#endif
