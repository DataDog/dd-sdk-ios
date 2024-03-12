/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Errors that can be thrown when parsing a WebView message
internal enum WebViewMessageError: Error, Equatable {
    case dataSerialization(message: String)
    case invalidMessage(description: String)
}

/// A type forwarding type-less messages received from Datadog Browser SDK to either `DatadogRUM` or `DatadogLogs`.
internal final class MessageEmitter: InternalExtension<WebViewTracking>.AbstractMessageEmitter {
    /// The core for events forwarding.
    private weak var core: DatadogCoreProtocol?
    /// Log events sampler.
    let logsSampler: Sampler

    init(
        logsSampler: Sampler,
        core: DatadogCoreProtocol
    ) {
        self.logsSampler = logsSampler
        self.core = core
    }

    /// Sends a bag of data to the message bus
    /// - Parameter body: The data to send, it must be parsable to `WebViewMessage`
    override func send(body: Any, slotId: String? = nil) {
        guard let core = core else {
            return DD.logger.debug("Core must not be nil when using WebViewTracking")
        }

        do {
            guard let body = body as? String else {
                throw WebViewMessageError.invalidMessage(description: String(describing: body))
            }

            guard let data = body.data(using: .utf8) else {
                throw WebViewMessageError.dataSerialization(message: body)
            }

            let decoder = JSONDecoder()
            let event = try decoder.decode(WebViewMessage.self, from: data)

            switch event {
            case .log:
                send(log: event, in: core)
            case .rum:
                send(rum: event, in: core)
            case let .record(event, view):
                send(record: event, view: view, slotId: slotId, in: core)
            }
        } catch {
            DD.logger.error("Encountered an error when receiving web view event", error: error)
            core.telemetry.error("Encountered an error when receiving web view event", error: error)
        }
    }

    private func send(log message: WebViewMessage, in core: DatadogCoreProtocol) {
        guard logsSampler.sample() else {
            return
        }

        core.send(message: .webview(message), else: {
            DD.logger.warn("A WebView log is lost because Logging is disabled in the SDK")
        })
    }

    private func send(rum message: WebViewMessage, in core: DatadogCoreProtocol) {
        core.send(message: .webview(message), else: {
            DD.logger.warn("A WebView RUM event is lost because RUM is disabled in the SDK")
        })
    }

    private func send(record event: WebViewMessage.Event, view: WebViewMessage.View, slotId: String?, in core: DatadogCoreProtocol) {
        var event = event
        // inject the slotId
        event["slotId"] = slotId

        core.send(message: .webview(.record(event, view)), else: {
            DD.logger.warn("A WebView Replay record is lost because Session Replay is disabled in the SDK")
        })
    }
}
