/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(WatchKit)
import WatchKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Convenient wrapper to get system notifications independent from platform
public enum ApplicationNotifications {
    public static var didFinishLaunching: Notification.Name {
        #if canImport(WatchKit)
        WKExtension.applicationDidFinishLaunchingNotification
        #elseif canImport(UIKit)
        UIApplication.didFinishLaunchingNotification
        #elseif canImport(AppKit)
        NSApplication.didFinishLaunchingNotification
        #endif
    }

    public static var didBecomeActive: Notification.Name {
        #if canImport(WatchKit)
        WKExtension.applicationDidBecomeActiveNotification
        #elseif canImport(UIKit)
        UIApplication.didBecomeActiveNotification
        #elseif canImport(AppKit)
        NSApplication.didBecomeActiveNotification
        #endif
    }

    public static var willResignActive: Notification.Name {
        #if canImport(WatchKit)
        WKExtension.applicationWillResignActiveNotification
        #elseif canImport(UIKit)
        UIApplication.willResignActiveNotification
        #elseif canImport(AppKit)
        NSApplication.willResignActiveNotification
        #endif
    }

    public static var didEnterBackground: Notification.Name {
        #if canImport(WatchKit)
        WKExtension.applicationDidEnterBackgroundNotification
        #elseif canImport(UIKit)
        UIApplication.didEnterBackgroundNotification
        #elseif canImport(AppKit)
        NSApplication.didHideNotification
        #endif
    }

    public static var willEnterForeground: Notification.Name {
        #if canImport(WatchKit)
        WKExtension.applicationWillEnterForegroundNotification
        #elseif canImport(UIKit)
        UIApplication.willEnterForegroundNotification
        #elseif canImport(AppKit)
        NSApplication.willUnhideNotification
        #endif
    }
}
