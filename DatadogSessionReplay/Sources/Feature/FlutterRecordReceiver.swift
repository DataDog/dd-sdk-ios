/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

/// Receives Flutter session-replay records from the message bus and writes them to
/// the Session Replay feature scope, enriched with the current native RUM context.
internal struct FlutterRecordReceiver: FeatureMessageReceiver {
    internal struct FlutterRecord: Encodable {
        /// The RUM application ID of all records.
        let applicationID: String
        /// The RUM session ID of all records.
        let sessionID: String
        /// The RUM view ID of all records.
        let viewID: String
        /// Records enriched with further information.
        let records: [AnyEncodable]
    }

    /// Session Replay feature scope.
    let scope: FeatureScope

    func receive(message: DatadogInternal.FeatureMessage, from core: DatadogInternal.DatadogCoreProtocol) -> Bool {
        guard case let .flutterView(.record(records, viewID)) = message else {
            return false
        }
        NSLog("[DD-SR-N] receive(): \(records.count) record(s) for viewID=\(viewID)")
        scope.eventWriteContext { context, writer in
            guard
                let rumContext = context.additionalContext(ofType: RUMCoreContext.self),
                rumContext.sessionSampler.isSampled
            else {
                return
            }

            let record = FlutterRecord(
                applicationID: rumContext.applicationID,
                sessionID: rumContext.sessionID,
                viewID: viewID,
                records: records.map { AnyEncodable($0) }
            )

            writer.write(value: record)
            NSLog("[DD-SR-N] received \(records.count) record(s) for viewID=\(viewID)")
        }

        return true
    }
}
#endif
