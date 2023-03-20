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
        if sessionScopes.isEmpty && !applicationActive {
            startInitialSession(on: command, context: context, writer: writer)
        }

        if activeSession == nil && command.isUserInteraction {
            // No active sessions, start a new one
            startSession(on: command, context: context, writer: writer)
        }

        // Can't use scope(byPropagating:context:writer) because of the extra step in looking for sessions
        // that need a refresh
        sessionScopes = sessionScopes.compactMap({ scope in
            if scope.process(command: command, context: context, writer: writer) {
                // Returned true, keep the scope around, it still has work to do.
                return scope
            }

            if scope.isActive {
                // False, but still active means we timed out or expired, refresh the session
                return refresh(expiredSession: scope, on: command, context: context, writer: writer)
            }
            // Else, inactive and done processing events, remove
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

    private func startInitialSession(on command: RUMCommand, context: DatadogContext, writer: Writer) {
        applicationActive = true
        let initialSession = RUMSessionScope(
            isInitialSession: true,
            parent: self,
            startTime: context.sdkInitDate,
            dependencies: dependencies,
            isReplayBeingRecorded: context.srBaggage?.isReplayBeingRecorded
        )

        sessionScopes.append(initialSession)
        sessionScopeDidUpdate(initialSession)
        if context.applicationStateHistory.currentSnapshot.state != .background {
            // Immediately start the ApplicationLaunchView for the new session
            _ = initialSession.process(
                command: RUMApplicationStartCommand(
                    time: command.time,
                    attributes: command.attributes
                ),
                context: context,
                writer: writer
            )
        }
    }

    private func startSession(on command: RUMCommand, context: DatadogContext, writer: Writer) {
        let session = RUMSessionScope(isInitialSession: false, parent: self, startTime: command.time, dependencies: dependencies, isReplayBeingRecorded: context.srBaggage?.isReplayBeingRecorded
        )

        sessionScopes.append(session)
        sessionScopeDidUpdate(session)
    }

    private func sessionScopeDidUpdate(_ sessionScope: RUMSessionScope) {
        let sessionID = sessionScope.sessionUUID.rawValue.uuidString
        let isDiscarded = !sessionScope.isSampled
        dependencies.onSessionStart?(sessionID, isDiscarded)
    }
}
