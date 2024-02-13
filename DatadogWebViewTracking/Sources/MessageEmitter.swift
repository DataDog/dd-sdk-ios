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
    }

    /// Log events sampler.
    let logsSampler: Sampler
    /// The core for events forwarding.
    private weak var core: DatadogCoreProtocol?

    init(
        logsSampler: Sampler,
        core: DatadogCoreProtocol
    ) {
        self.logsSampler = logsSampler
        self.core = core
    }

    /// Sends a bag of data to the message bus.
    /// 
    /// - Parameter body: The data to send, it must be parsable to `WebViewMessage`
    override func send(body: Any) throws {
        guard let core = core else {
            return DD.logger.debug("Core must not be nil when using WebViewTracking")
        }

        let message = try WebViewMessage(body: body)

        switch message.eventType {
        case .log:
            if logsSampler.sample() {
                core.send(message: .baggage(key: MessageKeys.browserLog, value: message.event), else: {
                    DD.logger.warn("A WebView log is lost because Logging is disabled in the SDK")
                })
            }
        case .rum, .view, .action, .resource, .error, .longTask:
            core.send(message: .baggage(key: MessageKeys.browserRUMEvent, value: message.event), else: {
                DD.logger.warn("A WebView RUM event is lost because RUM is disabled in the SDK")
            })
        }
    }
}
