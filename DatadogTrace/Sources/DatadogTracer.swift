/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import OpenTelemetryApi

internal final class DatadogTracer: OTTracer, OpenTelemetryApi.Tracer {
    /// Trace feature scope.
    let featureScope: FeatureScope

    /// Global tags configured for Trace feature.
    let tags: [String: Encodable]
    /// Integration with Logging.
    let loggingIntegration: TracingWithLoggingIntegration

    let traceIDGenerator: TraceIDGenerator

    let spanIDGenerator: SpanIDGenerator

    /// Date provider for traces.
    let dateProvider: DateProvider

    let activeSpansPool = ActiveSpansPool()

    /// Local trace sampler. Used for spans created with tracer API.
    let localTraceSampler: Sampler
    /// Creates span events.
    let spanEventBuilder: SpanEventBuilder

    // MARK: - Initialization

    convenience init(
        core: DatadogCoreProtocol,
        localTraceSampler: Sampler,
        tags: [String: Encodable],
        traceIDGenerator: TraceIDGenerator,
        spanIDGenerator: SpanIDGenerator,
        dateProvider: DateProvider,
        loggingIntegration: TracingWithLoggingIntegration,
        spanEventBuilder: SpanEventBuilder
    ) {
        self.init(
            featureScope: core.scope(for: TraceFeature.self),
            localTraceSampler: localTraceSampler,
            tags: tags,
            traceIDGenerator: traceIDGenerator,
            spanIDGenerator: spanIDGenerator,
            dateProvider: dateProvider,
            loggingIntegration: loggingIntegration,
            spanEventBuilder: spanEventBuilder
        )
    }

    init(
        featureScope: FeatureScope,
        localTraceSampler: Sampler,
        tags: [String: Encodable],
        traceIDGenerator: TraceIDGenerator,
        spanIDGenerator: SpanIDGenerator,
        dateProvider: DateProvider,
        loggingIntegration: TracingWithLoggingIntegration,
        spanEventBuilder: SpanEventBuilder
    ) {
        self.featureScope = featureScope
        self.tags = tags
        self.traceIDGenerator = traceIDGenerator
        self.spanIDGenerator = spanIDGenerator
        self.dateProvider = dateProvider
        self.loggingIntegration = loggingIntegration
        self.localTraceSampler = localTraceSampler
        self.spanEventBuilder = spanEventBuilder
    }

    // MARK: - Open Tracing interface

    func startSpan(operationName: String, references: [OTReference]? = nil, tags: [String: Encodable]? = nil, startTime: Date? = nil) -> OTSpan {
        let parentSpanContext = references?.compactMap { $0.context.dd }.last ?? activeSpan?.context as? DDSpanContext
        return startSpan(
            spanContext: createSpanContext(parentSpanContext: parentSpanContext, using: localTraceSampler),
            operationName: operationName,
            tags: tags,
            startTime: startTime
        )
    }

    func startRootSpan(operationName: String, tags: [String: Encodable]? = nil, startTime: Date? = nil) -> OTSpan {
        return startSpan(
            spanContext: createSpanContext(parentSpanContext: nil, using: localTraceSampler),
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
        guard let context = reader.extract() as? DDSpanContext else {
            return nil
        }

        return DDSpanContext(
            traceID: context.traceID,
            spanID: context.spanID,
            parentSpanID: context.parentSpanID,
            baggageItems: context.baggageItems,
            sampleRate: localTraceSampler.samplingRate,
            isKept: context.isKept
        )
    }

    var activeSpan: OTSpan? {
        return activeSpansPool.getActiveSpan()
    }

    // MARK: - Internal

    internal func createSpanContext(parentSpanContext: DDSpanContext?, using sampler: Sampler) -> DDSpanContext {
        return DDSpanContext(
            traceID: parentSpanContext?.traceID ?? traceIDGenerator.generate(),
            spanID: spanIDGenerator.generate(),
            parentSpanID: parentSpanContext?.spanID,
            baggageItems: BaggageItems(parent: parentSpanContext?.baggageItems),
            sampleRate: parentSpanContext?.sampleRate ?? sampler.samplingRate,
            isKept: parentSpanContext?.isKept ?? sampler.sample()
        )
    }

    internal func startSpan(spanContext: DDSpanContext, operationName: String, tags: [String: Encodable]? = nil, startTime: Date? = nil) -> OTSpan {
        var combinedTags = self.tags
        if let userTags = tags {
            combinedTags.merge(userTags) { $1 }
        }

        // Initialize `LazySpanWriteContext` here in `startSpan()` so it captures the `DatadogContext` valid
        // for this moment of time. Added in RUM-699 to ensure spans are correctly linked with RUM information
        // available on the caller thread.
        let writer = LazySpanWriteContext(featureScope: featureScope)
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

        featureScope.set(
            context: context.map {
                SpanCoreContext(
                    traceID: String($0.traceID, representation: .hexadecimal),
                    spanID: String($0.spanID, representation: .decimal)
                )
            }
        )
    }
    // MARK: - OpenTelemetry

    func spanBuilder(spanName: String) -> OpenTelemetryApi.SpanBuilder {
        OTelSpanBuilder(
            active: false,
            attributes: [:],
            parent: .currentSpan,
            spanKind: .internal,
            spanName: spanName,
            startTime: nil,
            tracer: self
        )
    }
}
