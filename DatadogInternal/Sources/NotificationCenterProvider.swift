/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

#if os(macOS)
import AppKit
#endif

/// Provides notification centers used by Core.
public struct NotificationCenterProvider {
    /// Notification centre where application notifications are published.
    ///
    /// Usually `NotificationCenter.default`.
    public let applicationCenter: NotificationCenter

    #if os(macOS)
    /// Notification centre where workspace notifications are published.
    ///
    /// Usually `NSWorkspace.shared.notificationCenter`.
    public let workspaceCenter: NotificationCenter

    /// A `NotificationCenterProvider` instance with the default values used in production.
    public static var `default`: NotificationCenterProvider {
        .init(applicationCenter: .default, workspaceCenter: NSWorkspace.shared.notificationCenter)
    }

    public init(applicationCenter: NotificationCenter, workspaceCenter: NotificationCenter) {
        self.applicationCenter = applicationCenter
        self.workspaceCenter = workspaceCenter
    }
    #else
    /// A `NotificationCenterProvider` instance with the default values used in production.
    public static var `default`: NotificationCenterProvider {
        .init(applicationCenter: .default)
    }

    public init(applicationCenter: NotificationCenter) {
        self.applicationCenter = applicationCenter
    }
    #endif
}
