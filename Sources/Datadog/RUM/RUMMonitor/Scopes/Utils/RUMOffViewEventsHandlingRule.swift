/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Lightweight representation of current RUM session state, used to compute `RUMOffViewEventsHandlingRule`.
/// It gets serialized into `CrashContext` for computing the rule upon app process restart after crash.
internal struct RUMSessionState: Equatable, Codable {
    /// The session ID. Can be `.nullUUID` if the session was rejected by sampler.
    let sessionUUID: UUID
    /// If this is the very first session in the app process (`true`) or was re-created upon timeout (`false`).
    let isInitialSession: Bool
    /// If this session has ever tracked any view (used to reason about "application launch" events).
    let hasTrackedAnyView: Bool
    /// If the there was a Session Replay recording pending at the moment of starting this session (`nil` if SR Feature was not configured).
    let didStartWithReplay: Bool?
}

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
