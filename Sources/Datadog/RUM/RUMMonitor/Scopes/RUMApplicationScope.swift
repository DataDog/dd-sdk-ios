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

    func process(command: RUMCommand) -> Bool {
        if let teleDebugCommand = command as? RUMTelemetryDebugCommand {
            sendTelemetryDebugEvent(command: teleDebugCommand)
            return true
        } else if let teleErrorCommand = command as? RUMTelemetryErrorCommand {
            sendTelemetryErrorEvent(command: teleErrorCommand)
            return true
        }

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
            startTime: dependencies.sdkInitDate,
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

    private func sendTelemetryDebugEvent(command: RUMTelemetryDebugCommand) {
        let dateCorrection = dependencies.dateCorrector.currentCorrection
        let actionId = context.activeUserActionID?.toRUMDataFormat
        let viewId = context.activeViewID?.toRUMDataFormat
        let session: TelemetryDebugEvent.Session?
        if context.sessionID == RUMUUID.nullUUID {
            session = nil
        } else {
            session = .init(id: context.sessionID.toRUMDataFormat)
        }

        let event = TelemetryDebugEvent(
            dd: TelemetryDebugEvent.DD(),
            action: actionId.flatMap { .init(id: $0) },
            application: .init(id: context.rumApplicationID),
            date: dateCorrection.applying(to: command.time).timeIntervalSince1970.toInt64Milliseconds,
            service: "dd-sdk-ios",
            session: session,
            source: .ios,
            telemetry: TelemetryDebugEvent.Telemetry(message: command.message),
            version: dependencies.sdkVersion,
            view: viewId.flatMap { .init(id: $0) }
        )
        dependencies.eventOutput.write(event: event)
    }

    private func sendTelemetryErrorEvent(command: RUMTelemetryErrorCommand) {
        let dateCorrection = dependencies.dateCorrector.currentCorrection
        let actionId = context.activeUserActionID?.toRUMDataFormat
        let viewId = context.activeViewID?.toRUMDataFormat
        let event = TelemetryErrorEvent(
            dd: TelemetryErrorEvent.DD(),
            action: actionId.flatMap { .init(id: $0) },
            application: .init(id: context.rumApplicationID),
            date: dateCorrection.applying(to: command.time).timeIntervalSince1970.toInt64Milliseconds,
            service: "dd-sdk-ios",
            session: .init(id: context.sessionID.toRUMDataFormat),
            source: .ios,
            telemetry: TelemetryErrorEvent.Telemetry(error: TelemetryErrorEvent.Telemetry.Error(kind: command.kind, stack: command.stack), message: command.message),
            version: dependencies.sdkVersion,
            view: viewId.flatMap { .init(id: $0) }
        )
        dependencies.eventOutput.write(event: event)
    }
}
