/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Lightweight representation of current RUM application state, used to compute `RUMOffViewEventsHandlingRule`.
internal final class RUMApplicationState {
    /// The number of views created in this app other than `ApplicationLaunch`.
    var numberOfNonApplicationLaunchViewsCreated: Int
    /// If any previous session was explicitly stopped with `stopSession()` API.
    var wasAnySessionStopped: Bool
    /// If the previous session was explicitly stopped with `stopSession()` API.
    var wasPreviousSessionStopped: Bool

    init(
        numberOfNonApplicationLaunchViewsCreated: Int = 0,
        wasAnySessionStopped: Bool = false,
        wasPreviousSessionStopped: Bool = false
    ) {
        self.numberOfNonApplicationLaunchViewsCreated = numberOfNonApplicationLaunchViewsCreated
        self.wasAnySessionStopped = wasAnySessionStopped
        self.wasPreviousSessionStopped = wasPreviousSessionStopped
    }
}

/// The rule for handling RUM events which are tracked while there is no active view.
///
/// It isolates the logic behind starting artificial views like "ApplicationLaunch" or "Background". It is used by both RUM and Crash Reporting
/// to decide on how to track off-view events and crashes.
internal enum RUMOffViewEventsHandlingRule: Equatable {
    struct Constants {
        #if os(macOS)
        // macOS apps have no background state. This view holds events that arrive with no active view, for example after the last
        // window closes or in a menu bar app. It reuses the "Background" view handling, but keeps its own name so it is not read
        // as an iOS background period.
        // TODO: RUM-19085 Confirm the name and URL with the macOS RFC reviewers.
        /// The name of the view created when receiving an event while there is no active view.
        static let backgroundViewName = "NoActiveView"
        /// The url of the view created when receiving an event while there is no active view.
        static let backgroundViewURL = "com/datadog/no-active-view/view"
        #else
        /// The name of the view created when receiving an event while there is no active view and Background Events Tracking is enabled.
        static let backgroundViewName = "Background"
        /// The url of the view created when receiving an event while there is no active view and Background Events Tracking is enabled.
        static let backgroundViewURL = "com/datadog/background/view"
        #endif
        /// The name of the view created when receiving an event before any view was started in the initial session.
        static let applicationLaunchViewName = "ApplicationLaunch"
        /// The url of the view created when receiving an event before any view was started in the initial session.
        static let applicationLaunchViewURL = "com/datadog/application-launch/view"
    }

    /// Start "ApplicationLaunch" view to track the event.
    case handleInApplicationLaunchView
    /// Start "Background" view to track the event.
    case handleInBackgroundView
    /// Do not start any view (drop the event).
    case doNotHandle

    // MARK: - Init

    /// - Parameters:
    ///   - applicationState: RUM application state tracked since `RUM.enabled()`. Might be `nil` if the rule is applied for crash reports
    ///   processed after app is restarted.
    ///   - sessionState: RUM session state or `nil` if no session is started
    ///   - isAppInForeground: if the app is in foreground
    ///   - isBETEnabled: if Background Events Tracking feature is enabled in SDK configuration
    ///   - command: the command that is about to trigger the off-view event
    init(
        applicationState: RUMApplicationState?,
        sessionState: RUMSessionState?,
        isAppInForeground: Bool,
        isBETEnabled: Bool,
        command: RUMCommand?
    ) {
        #if os(macOS)
        // macOS apps are always in the foreground and often run with no view, so once a view was tracked, events with no active view
        // are kept by default, without Background Events Tracking.
        // As with the "Background" view, only commands with `canStartBackgroundView` start the view. App hangs and long tasks
        // do not start it, and are tracked once it exists.
        let tracksEventsWithNoActiveView = true
        #else
        let tracksEventsWithNoActiveView = !isAppInForeground && isBETEnabled
        #endif

        if let session = sessionState {
            guard session.isSampled else {
                self = .doNotHandle // when session is NOT sampled, do not track off-view events at all
                return
            }

            let thereWasNoViewInThisAppProcess = {
                if let applicationState {
                    return applicationState.numberOfNonApplicationLaunchViewsCreated == 0
                } else {
                    let thereWasNoViewInThisSession = !session.hasTrackedAnyView
                    return session.isInitialSession && thereWasNoViewInThisSession
                }
            }()

            if thereWasNoViewInThisAppProcess {
                if isAppInForeground {
                    if applicationState?.wasAnySessionStopped == true {
                        self = .doNotHandle
                    } else {
                        self = .handleInApplicationLaunchView
                    }
                } else if isBETEnabled {
                    if applicationState?.wasPreviousSessionStopped == true && command?.canStartBackgroundViewAfterSessionStop == false {
                        self = .doNotHandle
                    } else {
                        self = .handleInBackgroundView
                    }
                } else {
                    self = .doNotHandle
                }
            } else {
                if tracksEventsWithNoActiveView {
                    if applicationState?.wasPreviousSessionStopped == true && command?.canStartBackgroundViewAfterSessionStop == false {
                        self = .doNotHandle
                    } else {
                        self = .handleInBackgroundView
                    }
                } else {
                    self = .doNotHandle
                }
            }
        } else {
            if isAppInForeground {
                if applicationState?.wasAnySessionStopped == true {
                    self = .doNotHandle
                } else {
                    self = .handleInApplicationLaunchView
                }
            } else if isBETEnabled {
                if applicationState?.wasPreviousSessionStopped == true && command?.canStartBackgroundViewAfterSessionStop == false {
                    self = .doNotHandle
                } else {
                    self = .handleInBackgroundView
                }
            } else {
                self = .doNotHandle
            }
        }
    }
}
