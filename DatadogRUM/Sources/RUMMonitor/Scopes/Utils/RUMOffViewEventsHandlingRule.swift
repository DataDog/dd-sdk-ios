/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// The rule for handling RUM events which are tracked while there is no active view.
///
/// It isolates the logic behind starting artificial views like "ApplicationLaunch" or "Background". It is used by both RUM and Crash Reporting
/// to decide on how to track off-view events and crashes.
internal enum RUMOffViewEventsHandlingRule: Equatable {
    struct Constants {
        /// The name of the view created when receiving an event while there is no active view and Background Events Tracking is enabled.
        static let backgroundViewName = "Background"
        /// The url of the view created when receiving an event while there is no active view and Background Events Tracking is enabled.
        static let backgroundViewURL = "com/datadog/background/view"
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
    ///   - sessionState: RUM session state or `nil` if no session is started
    ///   - isAppInForeground: if the app is in foreground
    ///   - isBETEnabled: if Background Events Tracking feature is enabled in SDK configuration
    init(
        sessionState: RUMSessionState?,
        isAppInForeground: Bool,
        isBETEnabled: Bool
    ) {
        if let session = sessionState {
            guard session.sessionUUID != .nullUUID else {
                self = .doNotHandle // when session is sampled, do not track off-view events at all
                return
            }

            let thereWasNoViewInThisSession = !session.hasTrackedAnyView
            let thereWasNoViewInThisAppProcess = session.isInitialSession && thereWasNoViewInThisSession

            if thereWasNoViewInThisAppProcess {
                if isAppInForeground {
                    self = .handleInApplicationLaunchView
                } else if isBETEnabled {
                    self = .handleInBackgroundView
                } else {
                    self = .doNotHandle
                }
            } else {
                if !isAppInForeground && isBETEnabled {
                    self = .handleInBackgroundView
                } else {
                    self = .doNotHandle
                }
            }
        } else {
            if isAppInForeground {
                self = .handleInApplicationLaunchView
            } else if isBETEnabled {
                self = .handleInBackgroundView
            } else {
                self = .doNotHandle
            }
        }
    }
}
