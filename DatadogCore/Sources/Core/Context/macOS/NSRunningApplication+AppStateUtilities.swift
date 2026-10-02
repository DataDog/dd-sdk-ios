/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(macOS)
import AppKit

internal extension NSRunningApplication {
    static let loginWindowBundleID = "com.apple.loginwindow"

    /// `true` if this instance represents the login window process, `false` otherwise.
    var isLoginWindowProcess: Bool {
        bundleIdentifier == Self.loginWindowBundleID
    }
}
#endif
