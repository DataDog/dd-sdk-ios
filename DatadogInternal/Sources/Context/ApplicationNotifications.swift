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

/// Convenient wrapper to get system notifications independent from platform
public enum ApplicationNotifications {
    public static var didFinishLaunching: Notification.Name {
        #if canImport(WatchKit)
        WKExtension.applicationDidFinishLaunchingNotification
        #else
        UIApplication.didFinishLaunchingNotification
        #endif
    }

    public static var didBecomeActive: Notification.Name {
        #if canImport(WatchKit)
        WKExtension.applicationDidBecomeActiveNotification
        #else
        UIApplication.didBecomeActiveNotification
        #endif
    }

    public static var willResignActive: Notification.Name {
        #if canImport(WatchKit)
        WKExtension.applicationWillResignActiveNotification
        #else
        UIApplication.willResignActiveNotification
        #endif
    }

    public static var didEnterBackground: Notification.Name {
        #if canImport(WatchKit)
        WKExtension.applicationDidEnterBackgroundNotification
        #else
        UIApplication.didEnterBackgroundNotification
        #endif
    }

    public static var willEnterForeground: Notification.Name {
        #if canImport(WatchKit)
        WKExtension.applicationWillEnterForegroundNotification
        #else
        UIApplication.willEnterForegroundNotification
        #endif
    }
}
#endif
