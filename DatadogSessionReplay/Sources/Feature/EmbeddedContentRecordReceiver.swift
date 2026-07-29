/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct EmbeddedContentRecordReceiver: FeatureMessageReceiver {
    internal struct EmbeddedRecord: Encodable {
        /// The native RUM application ID associated with the records.
        let applicationID: String
        /// The native RUM session ID associated with the records.
        let sessionID: String
        /// The embedded RUM view ID associated with the records.
        let viewID: String
        /// The embedded Session Replay records.
        let records: [AnyEncodable]
    }

    /// Session Replay feature scope.
    let scope: FeatureScope

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .embeddedContent(message) = message else {
            return false
        }

        scope.eventWriteContext { context, writer in
            guard
                let rumContext = context.additionalContext(ofType: RUMCoreContext.self),
                rumContext.sessionSampler.isSampled
            else {
                return
            }

            let records = message.records.map { record in
                var record = record
                record["slotId"] = message.slotID
                return AnyEncodable(record)
            }

            writer.write(
                value: EmbeddedRecord(
                    applicationID: rumContext.applicationID,
                    sessionID: rumContext.sessionID,
                    viewID: message.viewID,
                    records: records
                )
            )
        }

        return true
    }
}
