/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(AppKit)
import AppKit

public enum WorkspaceNotifications {
    public static var didWake: Notification.Name {
        NSWorkspace.didWakeNotification
    }

    public static var willSleep: Notification.Name {
        NSWorkspace.willSleepNotification
    }

    public static var screensDidSleep: Notification.Name {
        NSWorkspace.screensDidSleepNotification
    }

    public static var screensDidWake: Notification.Name {
        NSWorkspace.screensDidWakeNotification
    }

    public static var sessionDidBecomeActive: Notification.Name {
        NSWorkspace.sessionDidBecomeActiveNotification
    }

    public static var sessionDidResignActive: Notification.Name {
        NSWorkspace.sessionDidResignActiveNotification
    }

    public static var didActivateApplication: Notification.Name {
        NSWorkspace.didActivateApplicationNotification
    }

    public static var didDeactivateApplication: Notification.Name {
        NSWorkspace.didDeactivateApplicationNotification
    }
}
#endif
