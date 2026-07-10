/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

#if canImport(AppKit)
import AppKit
#endif

#if os(macOS)
/// Wraps the necessary notification centers used by Core.
internal struct NotificationCenters {
    /// Notification centre where application notifications are published.
    ///
    /// Usually `NotificationCenter.default`.
    let applicationCenter: NotificationCenter

    /// Notification centre where workspace notifications are published.
    ///
    /// Usually `NSWorkspace.shared.notificationCenter`.
    let workspaceCenter: NotificationCenter

    /// A `NotificationCenters` instance with the default values used in production.
    static var `default`: NotificationCenters {
        .init(applicationCenter: .default, workspaceCenter: NSWorkspace.shared.notificationCenter)
    }
}
#else
/// Wraps the necessary notification centers used by Core.
internal struct NotificationCenters {
    /// Notification centre where application notifications are published.
    ///
    /// Usually `NotificationCenter.default`.
    let applicationCenter: NotificationCenter

    /// A `NotificationCenters` instance with the default values used in production.
    static var `default`: NotificationCenters {
        .init(applicationCenter: .default)
    }
}
#endif
