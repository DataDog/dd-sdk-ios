/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

/// A type forwarding type-less messages received from Datadog Browser SDK to either `DatadogRUM` or `DatadogLogs`.
internal final class MessageEmitter: InternalExtension<WebViewTracking>.AbstractMessageEmitter {
    enum MessageKeys {
        static let browserLog = "browser-log"
        static let browserRUMEvent = "browser-rum-event"
        static let browserReplayRecord = "browser-replay-record"
    }

    struct RecordBaggage: Encodable {
        let event: AnyCodable
        let viewId: String
        let slotId: String?
    }

    /// Log events sampler.
    let logsSampler: Sampler
    /// The core for events forwarding.
    private weak var core: DatadogCoreProtocol?

    init(
        core: DatadogCoreProtocol,
        logsSampler: Sampler
    ) {
        self.core = core
        self.logsSampler = logsSampler
    }

    /// Sends a bag of data to the message bus.
    /// 
    /// - Parameter body: The data to send, it must be parsable to `WebViewMessage`
    override func send(body: Any, slotId: String? = nil) throws {
        guard let core = core else {
            return DD.logger.debug("Core must not be nil when using WebViewTracking")
        }

        let message = try WebViewMessage(body: body)

        switch message {
        case let .log(event):
            send(log: event, in: core)
        case let .rum(event):
            send(rum: event, in: core)
        case let .record(event, view):
            send(record: event, viewId: view.id, slotId: slotId, in: core)
        }
    }

    private func send(log event: AnyCodable, in core: DatadogCoreProtocol) {
        guard logsSampler.sample() else {
            return
        }

        core.send(message: .baggage(key: MessageKeys.browserLog, value: event), else: {
            DD.logger.warn("A WebView log is lost because Logging is disabled in the SDK")
        })
    }

    private func send(rum event: AnyCodable, in core: DatadogCoreProtocol) {
        core.send(message: .baggage(key: MessageKeys.browserRUMEvent, value: event), else: {
            DD.logger.warn("A WebView RUM event is lost because RUM is disabled in the SDK")
        })
    }

    private func send(record event: AnyCodable, viewId: String, slotId: String?, in core: DatadogCoreProtocol) {
        let baggage = RecordBaggage(
            event: event,
            viewId: viewId,
            slotId: slotId
        )

        core.send(message: .baggage(key: MessageKeys.browserReplayRecord, value: baggage), else: {
            DD.logger.warn("A WebView Replay record is lost because Session Replay is disabled in the SDK")
        })
    }
}
