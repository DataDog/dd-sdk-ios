/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct LogsFeature: DatadogRemoteFeature {
    static let name = "logging"

    let requestBuilder: FeatureRequestBuilder

    let messageReceiver: FeatureMessageReceiver

    let logEventMapper: LogEventMapper?

    @ReadWriteLock
    private var attributes: [String: Encodable] = [:]

    /// Time provider.
    let dateProvider: DateProvider

    init(
        logEventMapper: LogEventMapper?,
        dateProvider: DateProvider,
        customIntakeURL: URL? = nil,
        telemetry: Telemetry = NOPTelemetry()
    ) {
        self.init(
            logEventMapper: logEventMapper,
            requestBuilder: RequestBuilder(
                customIntakeURL: customIntakeURL,
                telemetry: telemetry
            ),
            messageReceiver: CombinedFeatureMessageReceiver(
                LogMessageReceiver(logEventMapper: logEventMapper),
                CrashLogReceiver(dateProvider: dateProvider),
                WebViewLogReceiver()
            ),
            dateProvider: dateProvider
        )
    }

    init(
        logEventMapper: LogEventMapper?,
        requestBuilder: FeatureRequestBuilder,
        messageReceiver: FeatureMessageReceiver,
        dateProvider: DateProvider
    ) {
        self.logEventMapper = logEventMapper
        self.requestBuilder = requestBuilder
        self.messageReceiver = messageReceiver
        self.dateProvider = dateProvider
    }

    internal func addAttribute(forKey key: AttributeKey, value: AttributeValue) {
        _attributes.mutate { $0[key] = value }
    }

    internal func removeAttribute(forKey key: AttributeKey) {
        _attributes.mutate { $0.removeValue(forKey: key) }
    }

    internal func getAttributes() -> [String: Encodable] {
        return attributes
    }
}
