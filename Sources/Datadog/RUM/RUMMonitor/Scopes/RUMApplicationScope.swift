/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal class RUMApplicationScope: RUMScope, RUMContextProvider {
    // MARK: - Child Scopes

    // Whether the applciation is already active. Set to true
    // when the first session starts.
    private(set) var applicationActive = false

    /// Session scope. It gets created with the first event.
    /// Might be re-created later according to session duration constraints.
    private(set) var sessionScopes: [RUMSessionScope] = []

    /// Last active view from the last active  session. Used to restart the active view on a user action.
    private var lastActiveView: RUMViewScope?

    var activeSession: RUMSessionScope? {
        get { return sessionScopes.first(where: { $0.isActive }) }
    }

    // MARK: - Initialization

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
        if command is RUMSDKInitCommand {
            createInitialSession(on: command, context: context, writer: writer)
            return true
        }

        // If the application has not been yet activated and no sessions exist
        // -> create the initial session
        if sessionScopes.isEmpty && !applicationActive {
            createInitialSession(on: command, context: context, writer: writer)
        }

        // Create the application launch view on any command
        if !applicationActive {
            applicationStart(on: command, context: context, writer: writer)
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

            // proccss(command:context:writer) returned false, but if the scope is  still active
            // it means we timed out or expired and we need to refresh the session
            if scope.isActive {
                return refresh(expiredSession: scope, on: command, context: context, writer: writer)
            }

            // Else, an inactive scope is done processing events and can be removed
            return nil
        })

        // Sanity telemety, only end up with one active session
        if sessionScopes.filter({ $0.isActive }).count > 1 {
            DD.telemetry.error("An application has multiple active sessions!")
        }

        return activeSession != nil
    }

    // MARK: - Private

    private func refresh(expiredSession: RUMSessionScope, on command: RUMCommand, context: DatadogContext, writer: Writer) -> RUMSessionScope {
        let refreshedSession = RUMSessionScope(from: expiredSession, startTime: command.time, context: context)
        sessionScopeDidUpdate(refreshedSession)
        _ = refreshedSession.process(command: command, context: context, writer: writer)
        return refreshedSession
    }

    private func createInitialSession(on command: RUMCommand, context: DatadogContext, writer: Writer) {
        let initialSession = RUMSessionScope(
            isInitialSession: true,
            parent: self,
            startTime: context.sdkInitDate,
            dependencies: dependencies,
            hasReplay: context.srBaggage?.hasReplay
        )

        sessionScopes.append(initialSession)
        sessionScopeDidUpdate(initialSession)
    }

    private func applicationStart(on command: RUMCommand, context: DatadogContext, writer: Writer) {
        applicationActive = true

        guard context.applicationStateHistory.currentSnapshot.state != .background else {
            return
        }

        // Immediately start the ApplicationLaunchView for the new session
        _ = process(
            command: RUMApplicationStartCommand(
                time: command.time,
                attributes: command.attributes
            ),
            context: context,
            writer: writer
        )
    }

    private func startNewSession(on command: RUMCommand, context: DatadogContext, writer: Writer) {
        let resumingViewScope = command is RUMStartViewCommand ? nil : lastActiveView
        let newSession = RUMSessionScope(
            isInitialSession: false,
            parent: self,
            startTime: command.time,
            dependencies: dependencies,
            hasReplay: context.srBaggage?.hasReplay,
            resumingViewScope: resumingViewScope
        )
        lastActiveView = nil

        sessionScopes.append(newSession)
        sessionScopeDidUpdate(newSession)
    }

    private func sessionScopeDidUpdate(_ sessionScope: RUMSessionScope) {
        let sessionID = sessionScope.sessionUUID.rawValue.uuidString
        let isDiscarded = !sessionScope.isSampled
        dependencies.onSessionStart?(sessionID, isDiscarded)
    }
}
