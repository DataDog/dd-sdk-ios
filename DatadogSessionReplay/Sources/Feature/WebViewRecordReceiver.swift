/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal final class WebViewRecordReceiver: BusMessageReceiver {
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

    /// Session Replay feature scope.
    let scope: FeatureScope

    init(scope: FeatureScope) {
        self.scope = scope
    }

    func receive(message: WebViewRecordMessage, from core: DatadogCoreProtocol) {
        let event = message.event
        let view = message.view

        scope.eventWriteContext { context, writer in
            // Extract the `RUMContext` or `nil` if RUM session is not sampled:
            guard
                let rumContext = context.additionalContext(ofType: RUMCoreContext.self),
                rumContext.sessionSampler.isSampled
            else {
                return
            }

            var event = event

            if let timestamp = event["timestamp"] as? Int,
               let webViewContext = context.additionalContext(ofType: RUMWebViewContext.self),
               let offset = webViewContext.serverTimeOffset(forView: view.id) {
                event["timestamp"] = Int64(timestamp) + offset.dd.toInt64Milliseconds
            }

            let record = WebRecord(
                applicationID: rumContext.applicationID,
                sessionID: rumContext.sessionID,
                viewID: view.id,
                records: [AnyEncodable(event)]
            )

            writer.write(value: record)
        }
    }
}
