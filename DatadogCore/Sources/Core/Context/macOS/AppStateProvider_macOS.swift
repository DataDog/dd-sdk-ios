/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(AppKit)
import AppKit
import DatadogInternal

internal struct DefaultAppStateProvider: AppStateProvider {
    /// Provides information from framework APIs about the current application state.
    private let applicationStateProvider: MacOSApplicationStateProvider

    /// Creates a new `DefaultAppStateProvider`.
    ///
    /// - parameters:
    ///   - applicationStateProvider: Specific macOS application state provider, defaults
    ///   to `DefaultMacOSApplicationStateProvider`.
    init(applicationStateProvider: MacOSApplicationStateProvider = DefaultMacOSApplicationStateProvider()) {
        self.applicationStateProvider = applicationStateProvider
    }

    var current: AppState {
        // Note: based on empirical evidence, when an app is launched in macOS, sometimes NSApp.isActive returns
        // true, sometimes false, when called during the AppDelegate.applicationDidFinishLaunching method. This
        // happens even if the conditions the app is launched in are exactly the same (for example, double-clicking
        // it in the Finder). Do not assume NSApp.isActive will always return true if the application is launched
        // directly to the foreground.
        //
        // We cannot detect here if the system broadcasted the NSWorkspace.willSleepNotification notification
        // to running apps and the system is about to go to sleep. It's unlikely that is the case when
        // an application is being launched, assuming Datadog SDK is being initialized at app startup,
        // but it's possible.
        if applicationStateProvider.frontmostApplicationIsLoginWindow {
            return .lockScreen
        } else if applicationStateProvider.isHidden {
            return .hidden
        } else {
            return applicationStateProvider.isActive ? .active : .inactive
        }
    }
}
#endif
