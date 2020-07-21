/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Injection container for common dependencies used by all `RUMScopes`.
internal struct RUMScopeDependencies {
    let eventBuilder: RUMEventBuilder
    let eventOutput: RUMEventOutput
    let rumUUIDGenerator: RUMUUIDGenerator
}

internal class RUMApplicationScope: RUMScope {
    // MARK: - Child Scopes

    /// Session scope. It gets created with the first `.startView` event.
    /// Might be re-created later according to session duration constraints.
    private(set) var sessionScope: RUMScope?

    // MARK: - Initialization

    let dependencies: RUMScopeDependencies

    /// Tracks if the initial View was displayed by this application.
    private var didStartInitialView = false

    init(
        rumApplicationID: String,
        dependencies: RUMScopeDependencies
    ) {
        self.dependencies = dependencies
        self.context = RUMContext(
            rumApplicationID: rumApplicationID,
            sessionID: .nullUUID,
            activeViewID: nil,
            activeViewURI: nil,
            activeUserActionID: nil
        )
    }

    // MARK: - RUMScope

    let context: RUMContext

    func process(command: RUMCommand) -> Bool {
        if let currentSession = sessionScope {
            let keepCurrentSession = currentSession.process(command: command)
            if !keepCurrentSession {
                let refreshedSession = RUMSessionScope(parent: self, dependencies: dependencies, startTime: command.time)
                sessionScope = refreshedSession
                _ = refreshedSession.process(command: command)
            }
        } else {
            switch command {
            case let .startView(id, attributes, time):
                var startViewCommand = command

                if didStartInitialView == false {
                    startViewCommand = .startInitialView(id: id, attributes: attributes, time: time)
                    didStartInitialView = true
                }

                let newSession = RUMSessionScope(parent: self, dependencies: dependencies, startTime: command.time)
                sessionScope = newSession
                _ = newSession.process(command: startViewCommand)
            default:
                break
            }
        }

        return true
    }
}
