/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Injection container for common dependencies used by all `RUMScopes`.
internal struct RUMScopeDependencies {
    let dateProvider: DateProvider
    let eventBuilder: RUMEventBuilder
    let eventOutput: RUMEventOutput
}

internal class RUMApplicationScope: RUMScope {
    struct Constants {
        /// No-op session ID used before the real session is started.
        static let nullUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID()
    }

    // MARK: - Child Scopes

    /// Session scope. It gets created with the first `.startView` event.
    /// Might be re-created later according to session duration constraints.
    private(set) var sessionScope: RUMScope?

    // MARK: - Initialization

    let dependencies: RUMScopeDependencies

    init(
        rumApplicationID: String,
        dependencies: RUMScopeDependencies
    ) {
        self.dependencies = dependencies
        self.context = RUMContext(
            rumApplicationID: rumApplicationID,
            sessionID: Constants.nullUUID,
            activeViewID: nil,
            activeViewURI: nil,
            activeUserActionID: nil
        )
    }

    // MARK: - RUMScope

    let context: RUMContext

    func process(command: RUMCommand) -> Bool {
        if let currentSession = sessionScope {
            let shouldRefreshSession = currentSession.process(command: command)
            if shouldRefreshSession {
                let refreshedSession = RUMSessionScope(parent: self, dependencies: dependencies)
                sessionScope = refreshedSession
                _ = refreshedSession.process(command: command)
            }
        } else {
            switch command {
            case .startView:
                let newSession = RUMSessionScope(parent: self, dependencies: dependencies)
                sessionScope = newSession
                _ = newSession.process(command: command)
            default:
                break
            }
        }

        return false
    }
}
