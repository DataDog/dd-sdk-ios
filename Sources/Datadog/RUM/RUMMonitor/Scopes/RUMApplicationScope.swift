/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Injection container for common dependencies used by all `RUMScopes`.
internal struct RUMScopeDependencies {
    let userInfoProvider: RUMUserInfoProvider
    let connectivityInfoProvider: RUMConnectivityInfoProvider
    let eventBuilder: RUMEventBuilder
    let eventOutput: RUMEventOutput
    let rumUUIDGenerator: RUMUUIDGenerator
}

internal class RUMApplicationScope: RUMScope, RUMContextProvider {
    // MARK: - Child Scopes

    /// Session scope. It gets created with the first `.startView` event.
    /// Might be re-created later according to session duration constraints.
    private(set) var sessionScope: RUMSessionScope?
    /// RUM Sessions sampling rate.
    internal let samplingRate: Float

    // MARK: - Initialization

    let dependencies: RUMScopeDependencies

    init(
        rumApplicationID: String,
        dependencies: RUMScopeDependencies,
        samplingRate: Float
    ) {
        self.dependencies = dependencies
        self.samplingRate = samplingRate
        self.context = RUMContext(
            rumApplicationID: rumApplicationID,
            sessionID: .nullUUID,
            activeViewID: nil,
            activeViewURI: nil,
            activeUserActionID: nil
        )
    }

    // MARK: - RUMContextProvider

    let context: RUMContext

    // MARK: - RUMScope

    func process(command: RUMCommand) -> Bool {
        if let currentSession = sessionScope {
            sessionScope = manage(childScope: sessionScope, byPropagatingCommand: command)

            if sessionScope == nil { // if session expired
                refresh(expiredSession: currentSession, on: command)
            }
        } else {
            switch command {
            case let command as RUMStartViewCommand:
                startInitialSession(on: command)
            default:
                break
            }
        }

        return true
    }

    // MARK: - Private

    private func refresh(expiredSession: RUMSessionScope, on command: RUMCommand) {
        let refreshedSession = RUMSessionScope(from: expiredSession, startTime: command.time)
        sessionScope = refreshedSession
        _ = refreshedSession.process(command: command)
    }

    private func startInitialSession(on command: RUMStartViewCommand) {
        var startInitialViewCommand = command
        startInitialViewCommand.isInitialView = true

        let initialSession = RUMSessionScope(
            parent: self,
            dependencies: dependencies,
            samplingRate: samplingRate,
            startTime: command.time
        )

        sessionScope = initialSession
        _ = initialSession.process(command: startInitialViewCommand)
    }
}
