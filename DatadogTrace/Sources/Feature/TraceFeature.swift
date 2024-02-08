/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal final class TraceFeature: DatadogRemoteFeature {
    static let name = "tracing"

    let requestBuilder: FeatureRequestBuilder
    var messageReceiver: FeatureMessageReceiver { contextReceiver }

    let tracer: DatadogTracer
    let contextReceiver: ContextMessageReceiver

    init(
        in core: DatadogCoreProtocol,
        configuration: Trace.Configuration
    ) {
        self.requestBuilder = TracingRequestBuilder(
            customIntakeURL: configuration.customEndpoint,
            telemetry: core.telemetry
        )

        self.contextReceiver = ContextMessageReceiver()
        self.tracer = DatadogTracer(
            core: core,
            sampler: Sampler(samplingRate: configuration.debugSDK ? 100 : configuration.sampleRate),
            tags: configuration.tags ?? [:],
            tracingUUIDGenerator: configuration.traceIDGenerator,
            dateProvider: configuration.dateProvider,
            loggingIntegration: TracingWithLoggingIntegration(
                core: core,
                service: configuration.service,
                networkInfoEnabled: configuration.networkInfoEnabled
            ),
            spanEventBuilder: SpanEventBuilder(
                service: configuration.service,
                networkInfoEnabled: configuration.networkInfoEnabled,
                eventsMapper: configuration.eventMapper,
                bundleWithRUM: configuration.bundleWithRumEnabled,
                telemetry: core.telemetry
            )
        )

        // Send configuration telemetry:
        core.telemetry.configuration(useTracing: true)
    }
}
