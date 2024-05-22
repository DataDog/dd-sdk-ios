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

    /// The reason of ending a session.
    enum EndReason: String {
        /// The session timed out because it received no interaction for x minutes.
        /// See: ``Constants.sessionTimeoutDuration``.
        case timeOut
        /// The session expired because it exceeded max duration.
        /// See: ``Constants.sessionMaxDuration``.
        case maxDuration
        /// The session was ended manually with ``RUMMonitorProtocol.stopSession()`` API.
        case stopAPI
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
            dependencies.fatalErrorContext.sessionState = state
        }
    }

    // MARK: - Initialization

    unowned let parent: RUMContextProvider
    private let dependencies: RUMScopeDependencies

    /// Automatically detect background events by creating "Background" view if no other view is active
    internal let trackBackgroundEvents: Bool

    /// This Session UUID. Equals `.nullUUID` if the Session is sampled.
    let sessionUUID: RUMUUID
    /// The precondition that led to the creation of this session.
    /// TODO: RUM-1650 This should become non-optional after all preconditions are implemented.
    let startPrecondition: RUMSessionPrecondition?
    /// If events from this session should be sampled (send to Datadog).
    let isSampled: Bool
    /// If the session is currently active. Set to `false` upon reaching the `EndReason`.
    var isActive: Bool { endReason == nil }
    /// If this is the very first session created in the current app process (`false` for session created upon expiration of a previous one).
    let isInitialSession: Bool
    /// The start time of this Session, measured in device date. In initial session this is the time of SDK init.
    private let sessionStartTime: Date
    /// Time of the last RUM interaction noticed by this Session.
    private var lastInteractionTime: Date
    /// The reason why this session has ended or `nil` if it is still active.
    private(set) var endReason: EndReason?

    init(
        isInitialSession: Bool,
        parent: RUMContextProvider,
        startTime: Date,
        startPrecondition: RUMSessionPrecondition?,
        dependencies: RUMScopeDependencies,
        hasReplay: Bool?,
        resumingViewScope: RUMViewScope? = nil
    ) {
        self.parent = parent
        self.dependencies = dependencies
        self.isSampled = dependencies.sessionSampler.sample()
        self.startPrecondition = startPrecondition
        self.sessionUUID = isSampled ? dependencies.rumUUIDGenerator.generateUnique() : .nullUUID
        self.isInitialSession = isInitialSession
        self.sessionStartTime = startTime
        self.lastInteractionTime = startTime
        self.trackBackgroundEvents = dependencies.trackBackgroundEvents
        self.endReason = nil
        self.state = RUMSessionState(
            sessionUUID: sessionUUID.rawValue,
            isInitialSession: isInitialSession,
            hasTrackedAnyView: false,
            didStartWithReplay: hasReplay
        )

        if let viewScope = resumingViewScope {
            startView(
                isInitialView: false,
                dependencies: dependencies,
                identity: viewScope.identity,
                path: viewScope.viewPath,
                name: viewScope.viewName,
                attributes: viewScope.attributes,
                customTimings: [:],
                startTime: startTime,
                serverTimeOffset: viewScope.serverTimeOffset,
                hasReplay: hasReplay
            )
        }

        // Update fatal error context with recent RUM session state:
        dependencies.fatalErrorContext.sessionState = state

        // Notify Synthetics if needed
        if dependencies.syntheticsTest != nil && sessionUUID != .nullUUID {
            NSLog("_dd.session.id=" + sessionUUID.toRUMDataFormat)
        }
    }

    /// Creates a new Session upon expiration of the previous one.
    convenience init(
        from expiredSession: RUMSessionScope,
        startTime: Date,
        startPrecondition: RUMSessionPrecondition?,
        context: DatadogContext
    ) {
        self.init(
            isInitialSession: false,
            parent: expiredSession.parent,
            startTime: startTime,
            startPrecondition: startPrecondition,
            dependencies: expiredSession.dependencies,
            hasReplay: context.hasReplay
        )

        // Transfer active Views by creating new `RUMViewScopes` for their identity objects:
        self.viewScopes = expiredSession.viewScopes.map { expiredView in
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
        context.sessionPrecondition = startPrecondition
        return context
    }

    // MARK: - RUMScope

    func process(command: RUMCommand, context: DatadogContext, writer: Writer) -> Bool {
        if hasTimedOut(currentTime: command.time) {
            endReason = .timeOut
            return false // end this session (no longer keep the session scope)
        }
        if hasExpired(currentTime: command.time) {
            endReason = .maxDuration
            return false // end this session (no longer keep the session scope)
        }

        if command.isUserInteraction {
            lastInteractionTime = command.time
        }

        if !isSampled {
            // Make sure sessions end even if they are sampled
            if command is RUMStopSessionCommand {
                endReason = .stopAPI
                return false // end this session (no longer keep the session scope)
            }

            return true // keep this session until it gets ended by any `endReason`
        }

        var deactivating = false
        if isActive {
            if command is RUMStopSessionCommand {
                endReason = .stopAPI
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
            // If this session is active and there is no active view, update fatal error context accordingly, so eventual
            // error won't be associated to an inactive view and instead we will consider starting background view to track it.
            // We also want to send this as a session is being stopped.
            // It means that with Background Events Tracking disabled, eventual off-view crashes will be dropped
            // similar to how we drop other events.
            dependencies.fatalErrorContext.view = nil
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
        startView(
            isInitialView: isStartingInitialView,
            dependencies: dependencies,
            identity: command.identity,
            path: command.path,
            name: command.name,
            attributes: command.attributes,
            customTimings: [:],
            startTime: command.time,
            serverTimeOffset: context.serverTimeOffset,
            hasReplay: context.hasReplay
        )
    }

    private func startView(
        isInitialView: Bool,
        dependencies: RUMScopeDependencies,
        identity: ViewIdentifier,
        path: String,
        name: String,
        attributes: [AttributeKey: AttributeValue],
        customTimings: [String: Int64],
        startTime: Date,
        serverTimeOffset: TimeInterval,
        hasReplay: Bool?
    ) {
        let scope = RUMViewScope(
            isInitialView: isInitialView,
            parent: self,
            dependencies: dependencies,
            identity: identity,
            path: path,
            name: name,
            attributes: attributes,
            customTimings: customTimings,
            startTime: startTime,
            serverTimeOffset: serverTimeOffset
        )

        viewScopes.append(scope)

        let id = scope.viewUUID.toRUMDataFormat

        // Cache the view id at each view start
        dependencies.viewCache.insert(
            id: id,
            timestamp: startTime.timeIntervalSince1970.toInt64Milliseconds,
            hasReplay: hasReplay
        )
    }

    private func startApplicationLaunchView(on command: RUMApplicationStartCommand, context: DatadogContext, writer: Writer) {
        var startTime = sessionStartTime
        if context.launchTime?.isActivePrewarm == false, let processStartTime = context.launchTime?.launchDate {
            startTime = processStartTime
        }

        startView(
            isInitialView: true,
            dependencies: dependencies,
            identity: ViewIdentifier(RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL),
            path: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL,
            name: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName,
            attributes: command.attributes,
            customTimings: [:],
            startTime: startTime,
            serverTimeOffset: context.serverTimeOffset,
            hasReplay: context.hasReplay
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

        startView(
            isInitialView: isStartingInitialView,
            dependencies: dependencies,
            identity: ViewIdentifier(RUMOffViewEventsHandlingRule.Constants.backgroundViewURL),
            path: RUMOffViewEventsHandlingRule.Constants.backgroundViewURL,
            name: RUMOffViewEventsHandlingRule.Constants.backgroundViewName,
            attributes: command.attributes,
            customTimings: [:],
            startTime: command.time,
            serverTimeOffset: context.serverTimeOffset,
            hasReplay: context.hasReplay
        )
    }

    private func hasTimedOut(currentTime: Date) -> Bool {
        let timeElapsedSinceLastInteraction = currentTime.timeIntervalSince(lastInteractionTime)
        return timeElapsedSinceLastInteraction >= Constants.sessionTimeoutDuration
    }

    private func hasExpired(currentTime: Date) -> Bool {
        let sessionDuration = currentTime.timeIntervalSince(sessionStartTime)
        return sessionDuration >= Constants.sessionMaxDuration
    }
}
