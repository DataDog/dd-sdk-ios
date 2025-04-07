/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

@testable import DatadogTrace

// MARK: - Span Mocks

public struct NOPSpanWriteContext: SpanWriteContext {
    public init() {}
    public func spanWriteContext(_ block: @escaping (DatadogContext, Writer) -> Void) {}
}

extension DDSpan {
    public static func mockAny(in core: DatadogCoreProtocol) -> DDSpan {
        return mockWith(core: core)
    }

    public static func mockWith(
        tracer: DatadogTracer,
        context: DDSpanContext = .mockAny(),
        operationName: String = .mockAny(),
        startTime: Date = .mockAny(),
        tags: [String: Encodable] = [:],
        eventBuilder: SpanEventBuilder = .mockAny(),
        eventWriter: SpanWriteContext = NOPSpanWriteContext()
    ) -> DDSpan {
        return DDSpan(
            tracer: tracer,
            context: context,
            operationName: operationName,
            startTime: startTime,
            tags: tags,
            eventBuilder: eventBuilder,
            eventWriter: eventWriter
        )
    }

    public static func mockWith(
        core: DatadogCoreProtocol,
        context: DDSpanContext = .mockAny(),
        operationName: String = .mockAny(),
        startTime: Date = .mockAny(),
        tags: [String: Encodable] = [:],
        eventBuilder: SpanEventBuilder = .mockAny(),
        eventWriter: SpanWriteContext = NOPSpanWriteContext()
    ) -> DDSpan {
        return DDSpan(
            tracer: .mockAny(in: core),
            context: context,
            operationName: operationName,
            startTime: startTime,
            tags: tags,
            eventBuilder: eventBuilder,
            eventWriter: eventWriter
        )
    }
}

extension DDSpanContext {
    public static func mockAny() -> DDSpanContext {
        return mockWith()
    }

    public static func mockWith(
        traceID: TraceID = .mockAny(),
        spanID: SpanID = .mockAny(),
        parentSpanID: SpanID? = .mockAny(),
        baggageItems: BaggageItems = .mockAny(),
        sampleRate: Float = .mockAny(),
        isKept: Bool = .mockAny()
    ) -> DDSpanContext {
        return DDSpanContext(
            traceID: traceID,
            spanID: spanID,
            parentSpanID: parentSpanID,
            baggageItems: baggageItems,
            sampleRate: sampleRate,
            isKept: isKept
        )
    }
}

extension BaggageItems {
    public static func mockAny() -> BaggageItems {
        return BaggageItems()
    }
}

// MARK: - Component Mocks

extension DatadogTracer {
    public static func mockAny(in core: DatadogCoreProtocol) -> DatadogTracer {
        return mockWith(core: core)
    }

    public static func mockWith(
        core: DatadogCoreProtocol,
        localTraceSampler: Sampler = .mockKeepAll(),
        tags: [String: Encodable] = [:],
        traceIDGenerator: TraceIDGenerator = DefaultTraceIDGenerator(),
        spanIDGenerator: SpanIDGenerator = DefaultSpanIDGenerator(),
        dateProvider: DateProvider = SystemDateProvider(),
        spanEventBuilder: SpanEventBuilder = .mockAny(),
        loggingIntegration: TracingWithLoggingIntegration = .mockAny()
    ) -> DatadogTracer {
        return DatadogTracer(
            core: core,
            localTraceSampler: localTraceSampler,
            tags: tags,
            traceIDGenerator: traceIDGenerator,
            spanIDGenerator: spanIDGenerator,
            dateProvider: dateProvider,
            loggingIntegration: loggingIntegration,
            spanEventBuilder: spanEventBuilder
        )
    }
}

extension TracingWithLoggingIntegration {
    public static func mockAny() -> TracingWithLoggingIntegration {
        return TracingWithLoggingIntegration(
            core: NOPDatadogCore(),
            service: .mockAny(),
            networkInfoEnabled: .mockAny()
        )
    }
}

extension ContextMessageReceiver {
    public static func mockAny() -> ContextMessageReceiver {
        return ContextMessageReceiver()
    }
}

extension SpanEventBuilder {
    public static func mockAny() -> SpanEventBuilder {
        return mockWith()
    }

    public static func mockWith(
        service: String = .mockAny(),
        networkInfoEnabled: Bool = false,
        eventsMapper: SpanEventMapper? = nil,
        bundleWithRUM: Bool = false,
        telemetry: Telemetry = NOPTelemetry()
    ) -> SpanEventBuilder {
        return SpanEventBuilder(
            service: service,
            networkInfoEnabled: networkInfoEnabled,
            eventsMapper: eventsMapper,
            bundleWithRUM: bundleWithRUM,
            telemetry: telemetry
        )
    }
}
