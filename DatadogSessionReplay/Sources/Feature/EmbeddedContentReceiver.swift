/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

internal struct EmbeddedContentReceiver: FeatureMessageReceiver {
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

    /// Shared writer for native and embedded Session Replay resources.
    let resourcesWriter: ResourcesWriting

    /// Shared publisher for native and embedded Session Replay record counts.
    let srContextPublisher: SRContextPublisher

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .embeddedContent(embeddedContentMessage) = message else {
            return false
        }

        scope.eventWriteContext { context, writer in
            guard
                let rumContext = context.additionalContext(ofType: RUMCoreContext.self),
                rumContext.sessionSampler.isSampled
            else {
                return
            }

            switch embeddedContentMessage {
            case .records(let batch):
                guard !batch.records.isEmpty else {
                    return
                }

                let records = batch.records.map { record in
                    var record = record
                    record["slotId"] = batch.slotID
                    return AnyEncodable(record)
                }

                writer.write(
                    value: EmbeddedRecord(
                        applicationID: rumContext.applicationID,
                        sessionID: rumContext.sessionID,
                        viewID: batch.viewID,
                        records: records
                    )
                )
                srContextPublisher.incrementRecordCount(
                    by: Int64(records.count),
                    forViewID: batch.viewID
                )
            case .resource(let resource):
                resourcesWriter.write(
                    resources: [
                        EnrichedResource(
                            identifier: resource.identifier,
                            data: resource.data,
                            mimeType: resource.mimeType,
                            context: .init(rumContext.applicationID)
                        )
                    ]
                )
            }
        }

        return true
    }
}
#endif
