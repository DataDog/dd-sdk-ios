/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@_spi(Internal)
import DatadogInternal

internal struct WebViewRecordReceiver: FeatureMessageReceiver {
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

    func receive(message: DatadogInternal.FeatureMessage, from core: DatadogInternal.DatadogCoreProtocol) -> Bool {
        let record: WebViewMessage
        let receipt: WebViewMessageWithRUMContext?
        let legacyRegistration: RUMLegacyWebViewTrackingReceipt?
        switch message {
        case .webview(let message):
            record = message
            receipt = nil
            legacyRegistration = nil
        case let .payload(message as WebViewMessageWithRUMContext):
            record = message.message
            receipt = message
            legacyRegistration = nil
        case let .payload(message as WebViewMessageWithLegacyRUMRegistration):
            record = message.message
            receipt = nil
            legacyRegistration = message.receipt
        default:
            return false
        }
        guard case let .record(event, view) = record else {
            return false
        }

        scope.eventWriteContext { context, writer in
            guard legacyRegistration?.isCurrent != false else {
                return
            }
            let current = context.additionalContext(ofType: RUMCoreContext.self)
            let rumContext: RUMCoreContext?
            if let receipt {
                rumContext = receipt.rumContext(in: core, sessionID: current?.sessionID)
            } else {
                rumContext = current
            }
            guard let rumContext, rumContext.sessionSampler.isSampled else {
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

        return true
    }
}
