/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct DatadogTraceFeature: DatadogRemoteFeature {
    static let name = "tracing"

    let requestBuilder: FeatureRequestBuilder

    let messageReceiver: FeatureMessageReceiver

    let tracer: DatadogTracer

    init(
        core: DatadogCoreProtocol,
        uuidGenerator: TracingUUIDGenerator,
        spanEventMapper: SpanEventMapper?,
        dateProvider: DateProvider,
        configuration: DatadogTracer.Configuration
    ) {
        let receiver = TracingMessageReceiver()
        self.init(
            tracer: .init(
                core: core,
                configuration: configuration,
                spanEventMapper: spanEventMapper,
                tracingUUIDGenerator: uuidGenerator,
                dateProvider: dateProvider,
                rumIntegration: configuration.bundleWithRUM ? receiver.rum : nil,
                loggingIntegration: TracingWithLoggingIntegration(
                    core: core,
                    tracerConfiguration: configuration
                )
            ),
            requestBuilder: TracingRequestBuilder(intake: configuration.intake),
            messageReceiver: receiver
        )
    }

    init(
        tracer: DatadogTracer,
        requestBuilder: FeatureRequestBuilder,
        messageReceiver: FeatureMessageReceiver
    ) {
        self.tracer = tracer
        self.requestBuilder = requestBuilder
        self.messageReceiver = messageReceiver
    }
}
