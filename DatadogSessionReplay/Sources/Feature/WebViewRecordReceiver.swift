/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal final class WebViewRecordReceiver: FeatureMessageReceiver {
    internal struct WebRecord: Encodable {
        /// The RUM application ID of all records.
        let applicationID: String
        /// The RUM session ID of all records.
        let sessionID: String
        /// The RUM view ID of all records.
        let viewID: String
        /// Records enriched with further information.
        let records: [AnyEncodable]
    }

    func receive(message: DatadogInternal.FeatureMessage, from core: DatadogInternal.DatadogCoreProtocol) -> Bool {
        guard case let .webview(.record(event, view)) = message else {
            return false
        }

        core.scope(for: SessionReplayFeature.name)?.eventWriteContext { context, writer in
            do {
                // Extract the `RUMContext` or `nil` if RUM session is not sampled:
                guard let rumContext = try context.baggages[RUMContext.key]?.decode(type: RUMContext.self) else {
                    return
                }

                var event = event

                if let timestamp = event["timestamp"] as? Int {
                    event["timestamp"] = Int64(timestamp) + self.offset(forView: view.id, context: context)
                }

                let record = WebRecord(
                    applicationID: rumContext.applicationID,
                    sessionID: rumContext.sessionID,
                    viewID: view.id,
                    records: [AnyEncodable(event)]
                )

                writer.write(value: record)
            } catch {
                core.telemetry
                    .error("Fails to decode RUM context from Session Replay", error: error)
                return
            }
        }

        return true
    }

    // MARK: - Time offsets

    private var offsets: [(id: String, value: Int64)] = []

    private func offset(forView id: String, context: DatadogContext) -> Int64 {
        if let found = offsets.first(where: { $0.id == id }) {
            return found.value
        }

        let offset = context.serverTimeOffset.toInt64Milliseconds
        offsets.insert((id, offset), at: 0)
        // only retain 3 offsets
        offsets = Array(offsets.prefix(3))
        return offset
    }
}
