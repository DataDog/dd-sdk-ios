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

    let applicationBundleIdentifier: String
    
    let sampler: Sampler

    let logEventMapper: LogEventMapper?

    /// Time provider.
    let dateProvider: DateProvider

    init(
        logEventMapper: LogEventMapper?,
        dateProvider: DateProvider,
        applicationBundleIdentifier: String,
        remoteLoggingSampler: Sampler,
        customIntakeURL: URL? = nil
    ) {
        self.init(
            applicationBundleIdentifier: applicationBundleIdentifier,
            logEventMapper: logEventMapper,
            sampler: remoteLoggingSampler,
            requestBuilder: RequestBuilder(customIntakeURL: customIntakeURL),
            messageReceiver: CombinedFeatureMessageReceiver(
                LogMessageReceiver(logEventMapper: logEventMapper),
                CrashLogReceiver(dateProvider: dateProvider),
                WebViewLogReceiver()
            ),
            dateProvider: dateProvider
        )
    }

    init(
        applicationBundleIdentifier: String,
        logEventMapper: LogEventMapper?,
        sampler: Sampler,
        requestBuilder: FeatureRequestBuilder,
        messageReceiver: FeatureMessageReceiver,
        dateProvider: DateProvider
    ) {
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.logEventMapper = logEventMapper
        self.sampler = sampler
        self.requestBuilder = requestBuilder
        self.messageReceiver = messageReceiver
        self.dateProvider = dateProvider
    }
}
