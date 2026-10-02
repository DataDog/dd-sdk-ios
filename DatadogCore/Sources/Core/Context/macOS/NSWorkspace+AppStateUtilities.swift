/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(macOS)
import AppKit

extension NSWorkspace {
    /// `true` is the login window is the active, frontmost process tracked by this workspace, `false` otherwise.
    var frontmostApplicationIsLoginWindow: Bool {
        frontmostApplication.map { $0.isLoginWindowProcess } ?? false
    }
}
#endif
