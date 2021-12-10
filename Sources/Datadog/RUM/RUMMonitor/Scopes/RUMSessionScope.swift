/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class RUMSessionScope: RUMScope, RUMContextProvider {
    struct Constants {
        /// If no interaction is registered within this period, a new session is started.
        static let sessionTimeoutDuration: TimeInterval = 15 * 60 // 15 minutes
        /// Maximum duration of a session. If it gets exceeded, a new session is started.
        static let sessionMaxDuration: TimeInterval = 4 * 60 * 60 // 4 hours
        /// The name of a view created when receiving an event while there is no active view and background events tracking  is enabled.
        static let backgroundViewName = "Background"
        /// The url of a view created when receiving an event while there is no active view and background events tracking is enabled.
        static let backgroundViewURL = "com/datadog/background/view"
        /// The name of a view created when receiving an event before any view was started in the initial session.
        static let applicationLaunchViewName = "ApplicationLaunch"
        /// The url of a view created when receiving an event before any view was started in the initial session.
        static let applicationLaunchViewURL = "com/datadog/application-launch/view"
    }

    // MARK: - Child Scopes

    /// Active View scopes. Scopes are added / removed when the View starts / stops displaying.
    private(set) var viewScopes: [RUMViewScope] = [] {
        didSet {
            hasTrackedAnyView = hasTrackedAnyView || !viewScopes.isEmpty
        }
    }
    /// If this session has ever tracked any view.
    private var hasTrackedAnyView = false

    // MARK: - Initialization

    unowned let parent: RUMContextProvider
    private let dependencies: RUMScopeDependencies

    /// Automatically detect background events by creating "Background" view if no other view is active
    internal let backgroundEventTrackingEnabled: Bool

    /// This Session UUID. Equals `.nullUUID` if the Session is sampled.
    let sessionUUID: RUMUUID
    /// Tells if events from this Session should be sampled-out (not send).
    let shouldBeSampledOut: Bool
    /// If this is the very first session created in the current app process (`false` for session created upon expiration of a previous one).
    let isInitialSession: Bool
    /// RUM Session sampling rate.
    private let samplingRate: Float
    /// The start time of this Session.
    private let sessionStartTime: Date
    /// Time of the last RUM interaction noticed by this Session.
    private var lastInteractionTime: Date

    init(
        isInitialSession: Bool,
        parent: RUMContextProvider,
        dependencies: RUMScopeDependencies,
        samplingRate: Float,
        startTime: Date,
        backgroundEventTrackingEnabled: Bool
    ) {
        self.parent = parent
        self.dependencies = dependencies
        self.samplingRate = samplingRate
        self.shouldBeSampledOut = RUMSessionScope.randomizeSampling(using: samplingRate)
        self.sessionUUID = shouldBeSampledOut ? .nullUUID : dependencies.rumUUIDGenerator.generateUnique()
        self.isInitialSession = isInitialSession
        self.sessionStartTime = startTime
        self.lastInteractionTime = startTime
        self.backgroundEventTrackingEnabled = backgroundEventTrackingEnabled
    }

    /// Creates a new Session upon expiration of the previous one.
    convenience init(
        from expiredSession: RUMSessionScope,
        startTime: Date
    ) {
        self.init(
            isInitialSession: false,
            parent: expiredSession.parent,
            dependencies: expiredSession.dependencies,
            samplingRate: expiredSession.samplingRate,
            startTime: startTime,
            backgroundEventTrackingEnabled: expiredSession.backgroundEventTrackingEnabled
        )

        // Transfer active Views by creating new `RUMViewScopes` for their identity objects:
        self.viewScopes = expiredSession.viewScopes.compactMap { expiredView in
            guard let expiredViewIdentifiable = expiredView.identity.identifiable else {
                return nil // if the underlying identifiable (`UIVIewController`) no longer exists, skip transferring its scope
            }
            return RUMViewScope(
                isInitialView: false,
                parent: self,
                dependencies: dependencies,
                identity: expiredViewIdentifiable,
                path: expiredView.viewPath,
                name: expiredView.viewName,
                attributes: expiredView.attributes,
                customTimings: expiredView.customTimings,
                startTime: startTime
            )
        }
    }

    // MARK: - RUMContextProvider

    var context: RUMContext {
        var context = parent.context
        context.sessionID = sessionUUID
        return context
    }

    // MARK: - RUMScope

    func process(command: RUMCommand) -> Bool {
        if timedOutOrExpired(currentTime: command.time) {
            return false // no longer keep this session
        }
        lastInteractionTime = command.time

        if shouldBeSampledOut {
            return true
        }

        // Consider starting an active view, "ApplicationLaunch" view or "Background" view
        if let startViewCommand = command as? RUMStartViewCommand {
            startView(on: startViewCommand)
        } else if isInitialSession && !hasTrackedAnyView { // if initial session with no views history
            let appInForeground = dependencies.appStateListener.history.currentState.isActive
            if appInForeground && command.canStartApplicationLaunchView { // when app is in foreground, start "ApplicationLaunch" view
                startApplicationLaunchView(on: command)
            } else if backgroundEventTrackingEnabled && command.canStartBackgroundView { // when app is in background and BET is enabled, start "Background" view
                startBackgroundView(on: command)
            }
        } else if backgroundEventTrackingEnabled && !hasActiveView && command.canStartBackgroundView { // if existing session with views history and BET is enabled
            startBackgroundView(on: command)
        }

        // Propagate command
        if !viewScopes.isEmpty {
            viewScopes = manage(childScopes: viewScopes, byPropagatingCommand: command)
        } else {
            userLogger.warn(
                """
                \(String(describing: command)) was detected, but no view is active. To track views automatically, try calling the
                DatadogConfiguration.Builder.trackUIKitRUMViews() method. You can also track views manually using
                the RumMonitor.startView() and RumMonitor.stopView() methods.
                """
            )
        }

        return true
    }

    /// If there is an active view.
    private var hasActiveView: Bool {
        return viewScopes.contains { $0.isActiveView }
    }

    // MARK: - RUMCommands Processing

    private func startView(on command: RUMStartViewCommand) {
        let isStartingInitialView = isInitialSession && !hasTrackedAnyView
        viewScopes.append(
            RUMViewScope(
                isInitialView: isStartingInitialView,
                parent: self,
                dependencies: dependencies,
                identity: command.identity,
                path: command.path,
                name: command.name,
                attributes: command.attributes,
                customTimings: [:],
                startTime: command.time
            )
        )
    }

    private func startApplicationLaunchView(on command: RUMCommand) {
        viewScopes.append(
            RUMViewScope(
                isInitialView: true,
                parent: self,
                dependencies: dependencies,
                identity: Constants.applicationLaunchViewURL,
                path: Constants.applicationLaunchViewURL,
                name: Constants.applicationLaunchViewName,
                attributes: command.attributes,
                customTimings: [:],
                startTime: command.time
            )
        )
    }

    private func startBackgroundView(on command: RUMCommand) {
        let isStartingInitialView = isInitialSession && !hasTrackedAnyView
        viewScopes.append(
            RUMViewScope(
                isInitialView: isStartingInitialView,
                parent: self,
                dependencies: dependencies,
                identity: Constants.backgroundViewURL,
                path: Constants.backgroundViewURL,
                name: Constants.backgroundViewName,
                attributes: command.attributes,
                customTimings: [:],
                startTime: command.time
            )
        )
    }

    private func timedOutOrExpired(currentTime: Date) -> Bool {
        let timeElapsedSinceLastInteraction = currentTime.timeIntervalSince(lastInteractionTime)
        let timedOut = timeElapsedSinceLastInteraction >= Constants.sessionTimeoutDuration

        let sessionDuration = currentTime.timeIntervalSince(sessionStartTime)
        let expired = sessionDuration >= Constants.sessionMaxDuration

        return timedOut || expired
    }

    private static func randomizeSampling(using samplingRate: Float) -> Bool {
        let sendSessionEvents = Float.random(in: 0.0..<100.0) < samplingRate
        return !sendSessionEvents
    }
}
