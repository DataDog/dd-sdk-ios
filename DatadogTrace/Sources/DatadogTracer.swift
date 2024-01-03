/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import OpenTelemetryApi

internal class DatadogTracer: OTTracer, OpenTelemetryApi.Tracer {
    internal weak var core: DatadogCoreProtocol?

    /// Global tags configured for Trace feature.
    let tags: [String: Encodable]
    let service: String?
    let networkInfoEnabled: Bool
    let spanEventMapper: ((SpanEvent) -> SpanEvent)?
    /// Queue ensuring thread-safety of the `Tracer` and `DDSpan` operations.
    let queue: DispatchQueue
    /// Integration with Core Context.
    let contextReceiver: ContextMessageReceiver
    /// Integration with Logging.
    let loggingIntegration: TracingWithLoggingIntegration

    let tracingUUIDGenerator: TraceIDGenerator

    /// Date provider for traces.
    let dateProvider: DateProvider

    let activeSpansPool = ActiveSpansPool()

    let sampler: Sampler

    /// Telemetry interface.
    let telemetry: Telemetry

    // MARK: - Initialization

    init(
        core: DatadogCoreProtocol,
        sampler: Sampler,
        tags: [String: Encodable],
        service: String?,
        networkInfoEnabled: Bool,
        spanEventMapper: ((SpanEvent) -> SpanEvent)?,
        tracingUUIDGenerator: TraceIDGenerator,
        dateProvider: DateProvider,
        contextReceiver: ContextMessageReceiver,
        loggingIntegration: TracingWithLoggingIntegration,
        telemetry: Telemetry = NOPTelemetry()
    ) {
        self.core = core
        self.tags = tags
        self.service = service
        self.networkInfoEnabled = networkInfoEnabled
        self.spanEventMapper = spanEventMapper
        self.queue = DispatchQueue(
            label: "com.datadoghq.tracer",
            target: .global(qos: .userInteractive)
        )

        self.tracingUUIDGenerator = tracingUUIDGenerator
        self.dateProvider = dateProvider
        self.contextReceiver = contextReceiver
        self.loggingIntegration = loggingIntegration
        self.sampler = sampler
        self.telemetry = telemetry
    }

    // MARK: - Open Tracing interface

    func startSpan(operationName: String, references: [OTReference]? = nil, tags: [String: Encodable]? = nil, startTime: Date? = nil) -> OTSpan {
        let parentSpanContext = references?.compactMap { $0.context.dd }.last ?? activeSpan?.context as? DDSpanContext
        return startSpan(
            spanContext: createSpanContext(parentSpanContext: parentSpanContext),
            operationName: operationName,
            tags: tags,
            startTime: startTime
        )
    }

    func startRootSpan(operationName: String, tags: [String: Encodable]? = nil, startTime: Date? = nil) -> OTSpan {
        return startSpan(
            spanContext: createSpanContext(parentSpanContext: nil),
            operationName: operationName,
            tags: tags,
            startTime: startTime
        )
    }

    func inject(spanContext: OTSpanContext, writer: OTFormatWriter) {
        writer.inject(spanContext: spanContext)
    }

    func extract(reader: OTFormatReader) -> OTSpanContext? {
        // TODO: RUMM-385 - make `HTTPHeadersReader` available in public API
        reader.extract()
    }

    var activeSpan: OTSpan? {
        return activeSpansPool.getActiveSpan()
    }

    // MARK: - Internal

    internal func createSpanContext(parentSpanContext: DDSpanContext? = nil) -> DDSpanContext {
        return DDSpanContext(
            traceID: parentSpanContext?.traceID ?? tracingUUIDGenerator.generate(),
            spanID: tracingUUIDGenerator.generate(),
            parentSpanID: parentSpanContext?.spanID,
            baggageItems: BaggageItems(parent: parentSpanContext?.baggageItems)
        )
    }

    internal func startSpan(spanContext: DDSpanContext, operationName: String, tags: [String: Encodable]? = nil, startTime: Date? = nil) -> OTSpan {
        var combinedTags = self.tags
        if let userTags = tags {
            combinedTags.merge(userTags) { $1 }
        }

        if let rumTags = contextReceiver.context.rum {
            combinedTags.merge(rumTags) { $1 }
        }

        let span = DDSpan(
            tracer: self,
            context: spanContext,
            operationName: operationName,
            startTime: startTime ?? dateProvider.now,
            tags: combinedTags,
            telemetry: telemetry
        )
        return span
    }

    internal func addSpan(span: DDSpan, activityReference: ActivityReference) {
        activeSpansPool.addSpan(span: span, activityReference: activityReference)
        updateCoreAttributes()
    }

    internal func removeSpan(activityReference: ActivityReference) {
        activeSpansPool.removeSpan(activityReference: activityReference)
        updateCoreAttributes()
    }

    private func updateCoreAttributes() {
        let context = activeSpan?.context as? DDSpanContext

        core?.set(
            baggage: context.map {
                SpanCoreContext(
                    traceID: String($0.traceID),
                    spanID: String($0.spanID)
                )
            },
            forKey: SpanCoreContext.key
        )
    }

    // MARK: - OpenTelemetry

    func spanBuilder(spanName: String) -> OpenTelemetryApi.SpanBuilder {
        OTelSpanBuilder(
            active: false,
            attributes: [:],
            parent: .currentSpan,
            spanKind: .client,
            spanName: spanName,
            startTime: nil,
            tracer: self
        )
    }
}
