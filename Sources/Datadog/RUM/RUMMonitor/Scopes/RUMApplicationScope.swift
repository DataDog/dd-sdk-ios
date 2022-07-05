/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class RUMApplicationScope: RUMScope, RUMContextProvider {
    // MARK: - Child Scopes

    /// Session scope. It gets created with the first event.
    /// Might be re-created later according to session duration constraints.
    private(set) var sessionScope: RUMSessionScope?

    // MARK: - Initialization

    let dependencies: RUMScopeDependencies

    init(dependencies: RUMScopeDependencies) {
        self.dependencies = dependencies
        self.context = RUMContext(
            rumApplicationID: dependencies.rumApplicationID,
            sessionID: .nullUUID,
            activeViewID: nil,
            activeViewPath: nil,
            activeViewName: nil,
            activeUserActionID: nil
        )
    }

    // MARK: - RUMContextProvider

    let context: RUMContext

    // MARK: - RUMScope

    func process(command: RUMCommand, context: DatadogV1Context, writer: Writer) -> Bool {
        if sessionScope == nil {
            startInitialSession(context: context)
        }

        if let currentSession = sessionScope {
            sessionScope = sessionScope?.scope(byPropagating: command, context: context, writer: writer)

            if sessionScope == nil { // if session expired
                refresh(expiredSession: currentSession, on: command, context: context, writer: writer)
            }
        }

        return true
    }

    // MARK: - Private

    private func refresh(expiredSession: RUMSessionScope, on command: RUMCommand, context: DatadogV1Context, writer: Writer) {
        let refreshedSession = RUMSessionScope(from: expiredSession, startTime: command.time, context: context)
        sessionScope = refreshedSession
        sessionScopeDidUpdate(refreshedSession)
        _ = refreshedSession.process(command: command, context: context, writer: writer)
    }

    private func startInitialSession(context: DatadogV1Context) {
        let initialSession = RUMSessionScope(
            isInitialSession: true,
            parent: self,
            startTime: context.sdkInitDate,
            dependencies: dependencies
        )
        sessionScope = initialSession
        sessionScopeDidUpdate(initialSession)
    }

    private func sessionScopeDidUpdate(_ sessionScope: RUMSessionScope) {
        let sessionID = sessionScope.sessionUUID.rawValue.uuidString
        let isDiscarded = !sessionScope.isSampled
        dependencies.onSessionStart?(sessionID, isDiscarded)
    }
}
