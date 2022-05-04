/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Sends Telemetry events to RUM.
///
/// `RUMTelemetry` complies to `Telemetry` protocol allowing
/// sending telemetry events accross features.
internal final class RUMTelemetry: Telemetry {
    let sdkVersion: String
    let applicationID: String
    let source: String
    let dateProvider: DateProvider
    let dateCorrector: DateCorrectorType

    /// Creates a RUM Telemetry instance.
    ///
    /// - Parameters:
    ///   - sdkVersion: The Datadog SDK version.
    ///   - applicationID: The application ID.
    ///   - dateProvider: Current device time provider.
    ///   - dateCorrector: Date correction for adjusting device time to server time.
    init(
        sdkVersion: String,
        applicationID: String,
        source: String,
        dateProvider: DateProvider,
        dateCorrector: DateCorrectorType
    ) {
        self.sdkVersion = sdkVersion
        self.applicationID = applicationID
        self.source = source
        self.dateProvider = dateProvider
        self.dateCorrector = dateCorrector
    }

    /// Sends a `TelemetryDebugEvent` event.
    /// see. https://github.com/DataDog/rum-events-format/blob/master/schemas/telemetry/debug-schema.json
    ///
    /// The current RUM context info is applied if available, including session ID, view ID,
    /// and action ID.
    ///
    /// - Parameter message: Body of the log
    func debug(_ message: String) {
        guard
            let monitor = Global.rum as? RUMMonitor,
            let writer = RUMFeature.instance?.storage.writer
        else {
            return
        }

        let date = dateCorrector.currentCorrection.applying(to: dateProvider.currentDate())

        monitor.contextProvider.async { context in
            let actionId = context.activeUserActionID?.toRUMDataFormat
            let viewId = context.activeViewID?.toRUMDataFormat
            let sessionId = context.sessionID == RUMUUID.nullUUID ? nil :context.sessionID.toRUMDataFormat

            let event = TelemetryDebugEvent(
                dd: .init(),
                action: actionId.map { .init(id: $0) },
                application: .init(id: self.applicationID),
                date: date.timeIntervalSince1970.toInt64Milliseconds,
                service: "dd-sdk-ios",
                session: sessionId.map { .init(id: $0) },
                source: TelemetryDebugEvent.Source(rawValue: self.source) ?? .ios,
                telemetry: .init(message: message),
                version: self.sdkVersion,
                view: viewId.map { .init(id: $0) }
            )

            writer.write(value: event)
        }
    }

    /// Sends a `TelemetryErrorEvent` event.
    /// see. https://github.com/DataDog/rum-events-format/blob/master/schemas/telemetry/error-schema.json
    ///
    /// The current RUM context info is applied if available, including session ID, view ID,
    /// and action ID.
    ///
    /// - Parameters:
    ///   - message: Body of the log
    ///   - kind: The error type or kind (or code in some cases).
    ///   - stack: The stack trace or the complementary information about the error.
    func error(_ message: String, kind: String?, stack: String?) {
        guard
            let monitor = Global.rum as? RUMMonitor,
            let writer = RUMFeature.instance?.storage.writer
        else {
            return
        }

        let date = dateCorrector.currentCorrection.applying(to: dateProvider.currentDate())

        monitor.contextProvider.async { context in
            let actionId = context.activeUserActionID?.toRUMDataFormat
            let viewId = context.activeViewID?.toRUMDataFormat
            let sessionId = context.sessionID == RUMUUID.nullUUID ? nil :context.sessionID.toRUMDataFormat

            let event = TelemetryErrorEvent(
                dd: .init(),
                action: actionId.map { .init(id: $0) },
                application: .init(id: self.applicationID),
                date: date.timeIntervalSince1970.toInt64Milliseconds,
                service: "dd-sdk-ios",
                session: sessionId.map { .init(id: $0) },
                source: TelemetryErrorEvent.Source(rawValue: self.source) ?? .ios,
                telemetry: .init(error: .init(kind: kind, stack: stack), message: message),
                version: self.sdkVersion,
                view: viewId.map { .init(id: $0) }
            )

            writer.write(value: event)
        }
    }
}
