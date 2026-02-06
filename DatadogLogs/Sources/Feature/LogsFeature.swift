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

    let backtraceReporter: BacktraceReporting?

    /// Global attributes attached to every log event.
    let attributes: SynchronizedAttributes

    /// Time provider.
    let dateProvider: DateProvider

    /// Allows overriding certain performance presets if needed. Default is nil.
    let performanceOverride: PerformancePresetOverride?

    init(
        logEventMapper: LogEventMapper?,
        dateProvider: DateProvider,
        customIntakeURL: URL? = nil,
        telemetry: Telemetry = NOPTelemetry(),
        backtraceReporter: BacktraceReporting? = nil
    ) {
        self.init(
            logEventMapper: logEventMapper,
            requestBuilder: RequestBuilder(
                customIntakeURL: customIntakeURL,
                telemetry: telemetry
            ),
            messageReceiver: CombinedFeatureMessageReceiver(
                LogMessageReceiver(logEventMapper: logEventMapper),
                WebViewLogReceiver()
            ),
            dateProvider: dateProvider,
            backtraceReporter: backtraceReporter
        )
    }

    init(
        logEventMapper: LogEventMapper?,
        requestBuilder: FeatureRequestBuilder,
        messageReceiver: FeatureMessageReceiver,
        dateProvider: DateProvider,
        backtraceReporter: BacktraceReporting?
    ) {
        self.logEventMapper = logEventMapper
        self.requestBuilder = requestBuilder
        self.messageReceiver = messageReceiver
        self.dateProvider = dateProvider
        self.backtraceReporter = backtraceReporter
        self.attributes = SynchronizedAttributes(attributes: [:])
        self.performanceOverride = nil
    }
}
