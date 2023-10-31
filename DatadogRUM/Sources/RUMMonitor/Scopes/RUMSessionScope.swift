/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal class RUMSessionScope: RUMScope, RUMContextProvider {
    struct Constants {
        /// If no interaction is registered within this period, a new session is started.
        static let sessionTimeoutDuration: TimeInterval = 15 * 60 // 15 minutes
        /// Maximum duration of a session. If it gets exceeded, a new session is started.
        static let sessionMaxDuration: TimeInterval = 4 * 60 * 60 // 4 hours
    }

    // MARK: - Child Scopes

    /// Active View scopes. Scopes are added / removed when the View starts / stops displaying.
    private(set) var viewScopes: [RUMViewScope] = [] {
        didSet {
            if !state.hasTrackedAnyView && !viewScopes.isEmpty {
                state = RUMSessionState(
                    sessionUUID: state.sessionUUID,
                    isInitialSession: state.isInitialSession,
                    hasTrackedAnyView: true,
                    didStartWithReplay: state.didStartWithReplay
                )
            }
        }
    }

    /// Information about this session state, shared with `CrashContext`.
    private var state: RUMSessionState {
        didSet {
            dependencies.core?.send(message: .baggage(key: RUMBaggageKeys.sessionState, value: state))
        }
    }

    // MARK: - Initialization

    unowned let parent: RUMContextProvider
    private let dependencies: RUMScopeDependencies

    /// Automatically detect background events by creating "Background" view if no other view is active
    internal let trackBackgroundEvents: Bool

    /// This Session UUID. Equals `.nullUUID` if the Session is sampled.
    let sessionUUID: RUMUUID
    /// If events from this session should be sampled (send to Datadog).
    let isSampled: Bool
    /// If the session is currently active. Set to false on a StopSession command
    var isActive: Bool
    /// If this is the very first session created in the current app process (`false` for session created upon expiration of a previous one).
    let isInitialSession: Bool
    /// The start time of this Session, measured in device date. In initial session this is the time of SDK init.
    private let sessionStartTime: Date
    /// Time of the last RUM interaction noticed by this Session.
    private var lastInteractionTime: Date

    init(
        isInitialSession: Bool,
        parent: RUMContextProvider,
        startTime: Date,
        dependencies: RUMScopeDependencies,
        hasReplay: Bool?,
        resumingViewScope: RUMViewScope? = nil
    ) {
        self.parent = parent
        self.dependencies = dependencies
        self.isSampled = dependencies.sessionSampler.sample()
        self.sessionUUID = isSampled ? dependencies.rumUUIDGenerator.generateUnique() : .nullUUID
        self.isInitialSession = isInitialSession
        self.sessionStartTime = startTime
        self.lastInteractionTime = startTime
        self.trackBackgroundEvents = dependencies.trackBackgroundEvents
        self.isActive = true
        self.state = RUMSessionState(
            sessionUUID: sessionUUID.rawValue,
            isInitialSession: isInitialSession,
            hasTrackedAnyView: false,
            didStartWithReplay: hasReplay
        )

        if let viewScope = resumingViewScope {
            viewScopes.append(
                RUMViewScope(
                    isInitialView: false,
                    parent: self,
                    dependencies: dependencies,
                    identity: viewScope.identity,
                    path: viewScope.viewPath,
                    name: viewScope.viewName,
                    attributes: viewScope.attributes,
                    customTimings: [:],
                    startTime: startTime,
                    serverTimeOffset: viewScope.serverTimeOffset
                )
            )
        }

        // Update `CrashContext` with recent RUM session state:
        dependencies.core?.send(message: .baggage(key: RUMBaggageKeys.sessionState, value: state))
    }

    /// Creates a new Session upon expiration of the previous one.
    convenience init(
        from expiredSession: RUMSessionScope,
        startTime: Date,
        context: DatadogContext
    ) {
        self.init(
            isInitialSession: false,
            parent: expiredSession.parent,
            startTime: startTime,
            dependencies: expiredSession.dependencies,
            hasReplay: context.hasReplay
        )

        // Transfer active Views by creating new `RUMViewScopes` for their identity objects:
        self.viewScopes = expiredSession.viewScopes.compactMap { expiredView in
            guard expiredView.identity.isIdentifiable else {
                return nil // if the underlying identifiable (`UIVIewController`) no longer exists, skip transferring its scope
            }
            return RUMViewScope(
                isInitialView: false,
                parent: self,
                dependencies: dependencies,
                identity: expiredView.identity,
                path: expiredView.viewPath,
                name: expiredView.viewName,
                attributes: expiredView.attributes,
                customTimings: expiredView.customTimings,
                startTime: startTime,
                serverTimeOffset: context.serverTimeOffset
            )
        }
    }

    // MARK: - RUMContextProvider

    var context: RUMContext {
        var context = parent.context
        context.sessionID = sessionUUID
        context.isSessionActive = isActive
        return context
    }

    // MARK: - RUMScope

    func process(command: RUMCommand, context: DatadogContext, writer: Writer) -> Bool {
        if timedOutOrExpired(currentTime: command.time) {
            return false // no longer keep this session
        }
        if command.isUserInteraction {
            lastInteractionTime = command.time
        }

        if !isSampled {
            // Make sure sessions end even if they are sampled
            if command is RUMStopSessionCommand {
                isActive = false
            }

            return isActive // discard all events in this session
        }

        var deactivating = false
        if isActive {
            if command is RUMStopSessionCommand {
                isActive = false
                deactivating = true
            } else if let startApplicationCommand = command as? RUMApplicationStartCommand {
                startApplicationLaunchView(on: startApplicationCommand, context: context, writer: writer)
            } else if let startViewCommand = command as? RUMStartViewCommand {
                // Start view scope explicitly on receiving "start view" command
                startView(on: startViewCommand, context: context)
            } else if !hasActiveView {
                handleOffViewCommand(command: command, context: context)
            }
        }

        // Propagate command
        viewScopes = viewScopes.scopes(byPropagating: command, context: context, writer: writer)

        if (isActive || deactivating) && !hasActiveView {
            // If this session is active and there is no active view, update `CrashContext` accordingly, so eventual crash
            // won't be associated to an inactive view and instead we will consider starting background view to track it.
            // We also want to send this as a session is being stopped.
            // It means that with Background Events Tracking disabled, eventual off-view crashes will be dropped
            // similar to how we drop other events.
            dependencies.core?.send(message: .baggage(key: RUMBaggageKeys.viewReset, value: true))
        }

        return isActive || !viewScopes.isEmpty
    }

    /// If there is an active view.
    private var hasActiveView: Bool {
        return viewScopes.contains { $0.isActiveView }
    }

    // MARK: - RUMCommands Processing

    private func startView(on command: RUMStartViewCommand, context: DatadogContext) {
        let isStartingInitialView = isInitialSession && !state.hasTrackedAnyView
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
                startTime: command.time,
                serverTimeOffset: context.serverTimeOffset
            )
        )
    }

    private func startApplicationLaunchView(on command: RUMApplicationStartCommand, context: DatadogContext, writer: Writer) {
        var startTime = sessionStartTime
        if context.launchTime?.isActivePrewarm == false,
           let processStartTime = context.launchTime?.launchDate {
            startTime = processStartTime
        }

        let scope = RUMViewScope(
            isInitialView: true,
            parent: self,
            dependencies: dependencies,
            identity: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL.asRUMViewIdentity(),
            path: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL,
            name: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName,
            attributes: command.attributes,
            customTimings: [:],
            startTime: startTime,
            serverTimeOffset: context.serverTimeOffset
        )

        viewScopes.append(
            scope
        )
    }

    private func handleOffViewCommand(command: RUMCommand, context: DatadogContext) {
        let handlingRule = RUMOffViewEventsHandlingRule(
            sessionState: state,
            isAppInForeground: context.applicationStateHistory.currentSnapshot.state.isRunningInForeground,
            isBETEnabled: trackBackgroundEvents
        )

        switch handlingRule {
        case .handleInBackgroundView where command.canStartBackgroundView:
            startBackgroundView(on: command, context: context)
        default:
            if !(command is RUMKeepSessionAliveCommand) { // it is expected to receive 'keep alive' while no active view (when tracking WebView events)
                // As no view scope will handle this command, warn the user on dropping it.
                DD.logger.warn(
                """
                \(String(describing: command)) was detected, but no view is active. To track views automatically, try calling the
                DatadogConfiguration.Builder.trackUIKitRUMViews() method. You can also track views manually using
                the RumMonitor.startView() and RumMonitor.stopView() methods.
                """
                )
            }
        }
    }

    private func startBackgroundView(on command: RUMCommand, context: DatadogContext) {
        let isStartingInitialView = isInitialSession && !state.hasTrackedAnyView
        viewScopes.append(
            RUMViewScope(
                isInitialView: isStartingInitialView,
                parent: self,
                dependencies: dependencies,
                identity: RUMOffViewEventsHandlingRule.Constants.backgroundViewURL.asRUMViewIdentity(),
                path: RUMOffViewEventsHandlingRule.Constants.backgroundViewURL,
                name: RUMOffViewEventsHandlingRule.Constants.backgroundViewName,
                attributes: command.attributes,
                customTimings: [:],
                startTime: command.time,
                serverTimeOffset: context.serverTimeOffset
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
}
