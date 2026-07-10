/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

#if canImport(UIKit)
import UIKit
#if canImport(WatchKit)
import WatchKit
#endif
#elseif canImport(AppKit)
import AppKit
#endif

/// Convenient wrapper to get system notifications independent from platform
public enum ApplicationNotifications {
    public static var didFinishLaunching: Notification.Name {
        #if canImport(WatchKit)
        WKExtension.applicationDidFinishLaunchingNotification
        #else
        DDApplication.didFinishLaunchingNotification
        #endif
    }

    public static var didBecomeActive: Notification.Name {
        #if canImport(WatchKit)
        WKExtension.applicationDidBecomeActiveNotification
        #else
        DDApplication.didBecomeActiveNotification
        #endif
    }

    public static var willResignActive: Notification.Name {
        #if canImport(WatchKit)
        WKExtension.applicationWillResignActiveNotification
        #else
        DDApplication.willResignActiveNotification
        #endif
    }

    // macOS has no concept of background apps in the same sense
    // iOS and watchOS do, so these notifications do not exist.
    #if canImport(WatchKit)
    public static var didEnterBackground: Notification.Name {
        WKExtension.applicationDidEnterBackgroundNotification
    }

    public static var willEnterForeground: Notification.Name {
        WKExtension.applicationWillEnterForegroundNotification
    }
    #elseif canImport(UIKit)
    public static var didEnterBackground: Notification.Name {
        UIApplication.didEnterBackgroundNotification
    }

    public static var willEnterForeground: Notification.Name {
        UIApplication.willEnterForegroundNotification
    }
    #endif

    #if os(macOS)
    public static var didHide: Notification.Name {
        NSApplication.didHideNotification
    }

    public static var didUnhide: Notification.Name {
        NSApplication.didUnhideNotification
    }

    public static var willTerminate: Notification.Name {
        NSApplication.willTerminateNotification
    }
    #endif
}
