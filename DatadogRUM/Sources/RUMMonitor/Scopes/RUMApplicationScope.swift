/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal class RUMApplicationScope: RUMScope, RUMContextProvider {
    // MARK: - Child Scopes

    // Whether the applciation is already active. Set to true
    // when the first session starts.
    private(set) var applicationActive = false

    /// Session scope. It gets created with the first event.
    /// Might be re-created later according to session duration constraints.
    private(set) var sessionScopes: [RUMSessionScope] = []

    /// Last active view from the last active session. Used to restart the active view on a user action.
    private var lastActiveView: RUMViewScope?

    /// The end reason from the last active session. Used as "start reason" for the new session.
    private var lastSessionEndReason: RUMSessionScope.EndReason?

    var activeSession: RUMSessionScope? {
        get { return sessionScopes.first(where: { $0.isActive }) }
    }

    // MARK: - Initialization

    /// Container bundling dependencies for this scope.
    let dependencies: RUMScopeDependencies

    init(dependencies: RUMScopeDependencies) {
        self.dependencies = dependencies
        self.context = RUMContext(
            rumApplicationID: dependencies.rumApplicationID,
            sessionID: .nullUUID,
            isSessionActive: false,
            activeViewID: nil,
            activeViewPath: nil,
            activeViewName: nil,
            activeUserActionID: nil
        )
    }

    // MARK: - RUMContextProvider

    let context: RUMContext

    // MARK: - RUMScope

    func process(command: RUMCommand, context: DatadogContext, writer: Writer) -> Bool {
        // `RUMSDKInitCommand` forces the creation of the initial session
        // Added in https://github.com/DataDog/dd-sdk-ios/pull/1278 to ensure that logs and traces
        // can be correlated with valid RUM session id (even if occurring before any user interaction).
        if command is RUMSDKInitCommand {
            createInitialSession(with: context, on: command)

            // If the app was started by a user (foreground & not prewarmed):
            if context.applicationStateHistory.currentSnapshot.state == .active && context.launchTime?.isActivePrewarm == false {
                // Start "ApplicationLaunch" view immediatelly:
                startApplicationLaunchView(on: command, context: context, writer: writer)
            }
            return true // always keep application scope
        }

        // If the application has not been yet activated and no sessions exist -> create the initial session
        // Added in https://github.com/DataDog/dd-sdk-ios/pull/1219 to start new session automatically when
        // a user action is sent (startView or addUserAction).
        if sessionScopes.isEmpty && !applicationActive {
            // This flow is likely stale code as`RUMSDKInitCommand` should already start the session before reaching this point
            dependencies.telemetry.debug("Starting initial session from lazy flow")
            createInitialSession(with: context, on: command)
        }

        // Create the application launch view on any command
        if !applicationActive {
            startApplicationLaunchView(on: command, context: context, writer: writer)
        }

        if activeSession == nil && command.isUserInteraction {
            // No active sessions, start a new one
            startNewSession(on: command, context: context, writer: writer)
        }

        if command is RUMStopSessionCommand {
            // Reach in and grab the last active view
            lastActiveView = activeSession?.viewScopes.first(where: { $0.isActiveView })
        }

        // Can't use scope(byPropagating:context:writer) because of the extra step in looking for sessions
        // that need a refresh
        sessionScopes = sessionScopes.compactMap({ scope in
            if scope.process(command: command, context: context, writer: writer) {
                // proccss(command:context:writer) returned true, so keep the scope around
                // as it it still has work to do.
                return scope
            }

            // proccss(command:context:writer) returned false, so the scope will be deallocated at the end of
            // this execution context. End the "RUM Session Ended" metric:
            defer { dependencies.sessionEndedMetric.endMetric(sessionID: scope.sessionUUID, with: context) }

            // proccss(command:context:writer) returned false, but if the scope is still active
            // it means the session reached one of the end reasons
            guard let endReason = scope.endReason else {
                // Sanity telemetry, we don't expect reaching this flow
                dependencies.telemetry.error("A session has ended with no 'end reason'")
                return nil
            }

            // Store "end reason" so it will be used as "start reason" for next session
            lastSessionEndReason = endReason

            switch endReason {
            case .timeOut, .maxDuration:
                // Replace this session scope with the scope for refreshed session:
                return refresh(expiredSession: scope, on: command, context: context, writer: writer)
            case .stopAPI:
                // Remove this session scope (a new on will be started upon receiving user interaction):
                return nil
            }
        })

        // Sanity telemety, only end up with one active session
        let activeSessions = sessionScopes.filter { $0.isActive }
        if activeSessions.count > 1 {
            dependencies.telemetry.error("An application has \(activeSessions.count) active sessions")
        }

        return true // always keep application scope
    }

    // MARK: - Private

    /// Sanity count to make sure initial session is created only once.
    private var didCreateInitialSessionCount = 0

    /// Starts initial RUM Session.
    private func createInitialSession(with context: DatadogContext, on command: RUMCommand) {
        if didCreateInitialSessionCount > 0 { // Sanity check
            dependencies.telemetry.error("Creating initial session \(didCreateInitialSessionCount) extra time(s) due to \(type(of: command)) (previous end reason: \(lastSessionEndReason?.rawValue ?? "unknown"))")
        }
        didCreateInitialSessionCount += 1

        var startPrecondition: RUMSessionPrecondition? = nil

        if context.launchTime?.isActivePrewarm == true {
            startPrecondition = .prewarm
        } else if context.applicationStateHistory.currentSnapshot.state == .background {
            startPrecondition = .backgroundLaunch
        } else {
            startPrecondition = .userAppLaunch
        }

        let initialSession = RUMSessionScope(
            isInitialSession: true,
            parent: self,
            startTime: context.sdkInitDate,
            startPrecondition: startPrecondition,
            context: context,
            dependencies: dependencies
        )

        lastSessionEndReason = nil
        sessionScopes.append(initialSession)
        sessionScopeDidUpdate(initialSession)
    }

    /// Starts new RUM Session immediately after previous one expires or time outs. It transfers some of the state from the expired session to the new one.
    private func refresh(expiredSession: RUMSessionScope, on command: RUMCommand, context: DatadogContext, writer: Writer) -> RUMSessionScope {
        var startPrecondition: RUMSessionPrecondition? = nil

        if lastSessionEndReason == .timeOut {
            startPrecondition = .inactivityTimeout
        } else if lastSessionEndReason == .maxDuration {
            startPrecondition = .maxDuration
        } else {
            dependencies.telemetry.error("Failed to determine session precondition for REFRESHED session with end reason: \(lastSessionEndReason?.rawValue ?? "unknown"))")
        }

        let refreshedSession = RUMSessionScope(
            from: expiredSession,
            startTime: command.time,
            startPrecondition: startPrecondition,
            context: context
        )
        sessionScopeDidUpdate(refreshedSession)
        lastSessionEndReason = nil
        _ = refreshedSession.process(command: command, context: context, writer: writer)
        return refreshedSession
    }

    /// Starts new RUM Session some time after previous one was ended with ``RUMMonitorProtocol.stopSession()`` API. It may re-activate the last view from previous session.
    private func startNewSession(on command: RUMCommand, context: DatadogContext, writer: Writer) {
        var startPrecondition: RUMSessionPrecondition? = nil

        if lastSessionEndReason == .stopAPI {
            startPrecondition = .explicitStop
        } else {
            dependencies.telemetry.error("Failed to determine session precondition for NEW session with end reason: \(lastSessionEndReason?.rawValue ?? "unknown"))")
        }

        if didCreateInitialSessionCount > 0 { // Sanity check
            // We assume this is not an initial session in the app (such is started with `RUMSDKInitCommand`:
            dependencies.telemetry.error("Starting NEW session on due to \(type(of: command)), but initial sesison never existed")
        }

        let resumingViewScope = command is RUMStartViewCommand ? nil : lastActiveView
        let newSession = RUMSessionScope(
            isInitialSession: false,
            parent: self,
            startTime: command.time,
            startPrecondition: startPrecondition,
            context: context,
            dependencies: dependencies,
            resumingViewScope: resumingViewScope
        )
        lastActiveView = nil
        lastSessionEndReason = nil

        sessionScopes.append(newSession)
        sessionScopeDidUpdate(newSession)
    }

    private func sessionScopeDidUpdate(_ sessionScope: RUMSessionScope) {
        let sessionID = sessionScope.sessionUUID.rawValue.uuidString
        let isDiscarded = !sessionScope.isSampled
        dependencies.onSessionStart?(sessionID, isDiscarded)
    }

    /// Forces the `ApplicationLaunchView` to be started.
    /// Added as part of https://github.com/DataDog/dd-sdk-ios/pull/1290 to separate creation of first view
    /// from creation of initial session due to receiving `RUMSDKInitCommand`. Starting from RUM-1649 the "application launch" view
    /// is started on SDK init only when the app is launched by user with no prewarming.
    private func startApplicationLaunchView(on command: RUMCommand, context: DatadogContext, writer: Writer) {
        applicationActive = true

        guard context.applicationStateHistory.currentSnapshot.state != .background else {
            return
        }

        // Immediately start the ApplicationLaunchView for the new session
        _ = process(
            command: RUMApplicationStartCommand(
                time: command.time,
                globalAttributes: command.globalAttributes,
                attributes: command.attributes
            ),
            context: context,
            writer: writer
        )
    }
}
