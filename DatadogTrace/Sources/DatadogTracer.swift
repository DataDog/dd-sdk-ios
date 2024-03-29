/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal class DatadogTracer: OTTracer {
    internal weak var core: DatadogCoreProtocol?

    /// Global tags configured for Trace feature.
    let tags: [String: Encodable]
    /// Integration with Logging.
    let loggingIntegration: TracingWithLoggingIntegration

    let tracingUUIDGenerator: TraceIDGenerator

    /// Date provider for traces.
    let dateProvider: DateProvider

    let activeSpansPool = ActiveSpansPool()

    let sampler: Sampler
    /// Creates span events.
    let spanEventBuilder: SpanEventBuilder

    // MARK: - Initialization

    init(
        core: DatadogCoreProtocol,
        sampler: Sampler,
        tags: [String: Encodable],
        tracingUUIDGenerator: TraceIDGenerator,
        dateProvider: DateProvider,
        loggingIntegration: TracingWithLoggingIntegration,
        spanEventBuilder: SpanEventBuilder
    ) {
        self.core = core
        self.tags = tags
        self.tracingUUIDGenerator = tracingUUIDGenerator
        self.dateProvider = dateProvider
        self.loggingIntegration = loggingIntegration
        self.sampler = sampler
        self.spanEventBuilder = spanEventBuilder
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
        guard let core = core else {
            return DDNoopGlobals.span
        }

        var combinedTags = self.tags
        if let userTags = tags {
            combinedTags.merge(userTags) { $1 }
        }

        // Initialize `LazySpanWriteContext` here in `startSpan()` so it captures the `DatadogContext` valid
        // for this moment of time. Added in RUM-699 to ensure spans are correctly linked with RUM information
        // available on the caller thread.
        let writer = LazySpanWriteContext(core: core)
        let span = DDSpan(
            tracer: self,
            context: spanContext,
            operationName: operationName,
            startTime: startTime ?? dateProvider.now,
            tags: combinedTags,
            eventBuilder: spanEventBuilder,
            eventWriter: writer
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
}
