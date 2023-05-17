/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal final class DatadogRUMFeature: DatadogRemoteFeature {
    static let name = "rum"

    let requestBuilder: FeatureRequestBuilder

    let messageReceiver: FeatureMessageReceiver

    let monitor: RUMMonitor

    let instrumentation: RUMInstrumentation

    init(
        monitor: RUMMonitor,
        instrumentation: RUMInstrumentation,
        requestBuilder: FeatureRequestBuilder,
        messageReceiver: FeatureMessageReceiver
    ) {
        self.monitor = monitor
        self.instrumentation = instrumentation
        self.requestBuilder = requestBuilder
        self.messageReceiver = messageReceiver
    }

    convenience init(in core: DatadogCoreProtocol, configuration: RUMConfiguration) {
        let monitor = RUMMonitor(
            core: core,
            dependencies: RUMScopeDependencies(
                core: core,
                configuration: configuration
            ),
            dateProvider: configuration.dateProvider
        )

        let instrumentation = RUMInstrumentation(
            configuration: configuration.instrumentation,
            dateProvider: configuration.dateProvider
        )

        instrumentation.publish(to: monitor)
        instrumentation.enable()

        self.init(
            monitor: monitor,
            instrumentation: instrumentation,
            requestBuilder: RequestBuilder(
                customIntakeURL: configuration.customIntakeURL
            ),
            messageReceiver: CombinedFeatureMessageReceiver(
                TelemetryReceiver(
                    dateProvider: configuration.dateProvider,
                    sampler: configuration.telemetrySampler,
                    configurationExtraSampler: configuration.configurationTelemetrySampler
                ),
                ErrorMessageReceiver(monitor: monitor),
                WebViewEventReceiver(
                    dateProvider: configuration.dateProvider,
                    commandSubscriber: monitor
                ),
                CrashReportReceiver(
                    applicationID: configuration.applicationID,
                    dateProvider: configuration.dateProvider,
                    sessionSampler: configuration.sessionSampler,
                    backgroundEventTrackingEnabled: configuration.backgroundEventTrackingEnabled,
                    uuidGenerator: configuration.uuidGenerator,
                    ciTest: configuration.testExecutionId.map { .init(testExecutionId: $0) }
                )
            )
        )
    }

    deinit {
        instrumentation.deinitialize()
    }
}

extension DatadogRUMFeature: Flushable {
    /// Awaits completion of all asynchronous operations.
    ///
    /// **blocks the caller thread**
    func flush() {
        monitor.queue.sync { }
    }
}
