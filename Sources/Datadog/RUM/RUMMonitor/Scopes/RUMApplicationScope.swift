/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal typealias RUMSessionListener = (String, Bool) -> Void

/// Injection container for common dependencies used by all `RUMScopes`.
internal struct RUMScopeDependencies {
    let appStateListener: AppStateListening
    let userInfoProvider: RUMUserInfoProvider
    let launchTimeProvider: LaunchTimeProviderType
    let connectivityInfoProvider: RUMConnectivityInfoProvider
    let eventBuilder: RUMEventBuilder
    let eventOutput: RUMEventOutput
    let rumUUIDGenerator: RUMUUIDGenerator
    /// Adjusts RUM events time (device time) to server time.
    let dateCorrector: DateCorrectorType
    /// Integration with Crash Reporting. It updates the crash context with RUM info.
    /// `nil` if Crash Reporting feature is not enabled.
    let crashContextIntegration: RUMWithCrashContextIntegration?

    let vitalCPUReader: SamplingBasedVitalReader
    let vitalMemoryReader: SamplingBasedVitalReader
    let vitalRefreshRateReader: ContinuousVitalReader

    let onSessionStart: RUMSessionListener?
}

internal class RUMApplicationScope: RUMScope, RUMContextProvider {
    // MARK: - Child Scopes

    /// Session scope. It gets created with the first event.
    /// Might be re-created later according to session duration constraints.
    private(set) var sessionScope: RUMSessionScope?

    /// RUM Sessions sampling rate.
    internal let samplingRate: Float

    /// The start time of the application, measured in device date. It equals the time of SDK init.
    private let applicationStartTime: Date

    /// Automatically detect background events
    internal let backgroundEventTrackingEnabled: Bool

    // MARK: - Initialization

    let dependencies: RUMScopeDependencies

    init(
        rumApplicationID: String,
        dependencies: RUMScopeDependencies,
        samplingRate: Float,
        applicationStartTime: Date,
        backgroundEventTrackingEnabled: Bool
    ) {
        self.dependencies = dependencies
        self.samplingRate = samplingRate
        self.applicationStartTime = applicationStartTime
        self.backgroundEventTrackingEnabled = backgroundEventTrackingEnabled
        self.context = RUMContext(
            rumApplicationID: rumApplicationID,
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

    func process(command: RUMCommand) -> Bool {
        if sessionScope == nil {
            startInitialSession()
        }

        if let currentSession = sessionScope {
            sessionScope = manage(childScope: sessionScope, byPropagatingCommand: command)

            if sessionScope == nil { // if session expired
                refresh(expiredSession: currentSession, on: command)
            }
        }

        return true
    }

    // MARK: - Private

    private func refresh(expiredSession: RUMSessionScope, on command: RUMCommand) {
        let refreshedSession = RUMSessionScope(from: expiredSession, startTime: command.time)
        sessionScope = refreshedSession
        sessionScopeDidUpdate(refreshedSession)
        _ = refreshedSession.process(command: command)
    }

    private func startInitialSession() {
        let initialSession = RUMSessionScope(
            isInitialSession: true,
            parent: self,
            dependencies: dependencies,
            samplingRate: samplingRate,
            startTime: applicationStartTime,
            backgroundEventTrackingEnabled: backgroundEventTrackingEnabled
        )
        sessionScope = initialSession
        sessionScopeDidUpdate(initialSession)
    }

    private func sessionScopeDidUpdate(_ sessionScope: RUMSessionScope) {
        let sessionID = sessionScope.sessionUUID.rawValue.uuidString
        dependencies.onSessionStart?(sessionID, sessionScope.shouldBeSampledOut)
    }
}
