/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import TestUtilities
import DatadogInternal

@testable import DatadogTrace

extension DatadogCoreProxy {
    func waitAndReturnSpanMatchers(file: StaticString = #file, line: UInt = #line) throws -> [SpanMatcher] {
        return try waitAndReturnEventsData(ofFeature: TraceFeature.name)
            .map { eventData in try SpanMatcher.fromJSONObjectData(eventData) }
    }
}

// MARK: - Span Mocks

extension DDSpan {
    static func mockAny(in core: DatadogCoreProtocol) -> DDSpan {
        return mockWith(core: core)
    }

    static func mockWith(
        tracer: DatadogTracer,
        context: DDSpanContext = .mockAny(),
        operationName: String = .mockAny(),
        startTime: Date = .mockAny(),
        tags: [String: Encodable] = [:]
    ) -> DDSpan {
        return DDSpan(
            tracer: tracer,
            context: context,
            operationName: operationName,
            startTime: startTime,
            tags: tags
        )
    }

    static func mockWith(
        core: DatadogCoreProtocol,
        context: DDSpanContext = .mockAny(),
        operationName: String = .mockAny(),
        startTime: Date = .mockAny(),
        tags: [String: Encodable] = [:]
    ) -> DDSpan {
        return DDSpan(
            tracer: .mockAny(in: core),
            context: context,
            operationName: operationName,
            startTime: startTime,
            tags: tags
        )
    }
}

extension DDSpanContext {
    static func mockAny() -> DDSpanContext {
        return mockWith()
    }

    static func mockWith(
        traceID: TraceID = .mockAny(),
        spanID: TraceID = .mockAny(),
        parentSpanID: TraceID? = .mockAny(),
        baggageItems: BaggageItems = .mockAny()
    ) -> DDSpanContext {
        return DDSpanContext(
            traceID: traceID,
            spanID: spanID,
            parentSpanID: parentSpanID,
            baggageItems: baggageItems
        )
    }
}

extension BaggageItems {
    static func mockAny() -> BaggageItems {
        return BaggageItems()
    }
}

// MARK: - Component Mocks

extension DatadogTracer {
    static func mockAny(in core: DatadogCoreProtocol) -> DatadogTracer {
        return mockWith(core: core)
    }

    static func mockWith(
        core: DatadogCoreProtocol,
        sampler: Sampler = .mockKeepAll(),
        tags: [String: Encodable] = [:],
        service: String? = nil,
        networkInfoEnabled: Bool = true,
        spanEventMapper: ((SpanEvent) -> SpanEvent)? = nil,
        tracingUUIDGenerator: TraceIDGenerator = DefaultTraceIDGenerator(),
        dateProvider: DateProvider = SystemDateProvider(),
        contextReceiver: ContextMessageReceiver = .mockAny(),
        loggingIntegration: TracingWithLoggingIntegration = .mockAny()
    ) -> DatadogTracer {
        return DatadogTracer(
            core: core,
            sampler: sampler,
            tags: tags,
            service: service,
            networkInfoEnabled: networkInfoEnabled,
            spanEventMapper: spanEventMapper,
            tracingUUIDGenerator: tracingUUIDGenerator,
            dateProvider: dateProvider,
            contextReceiver: contextReceiver,
            loggingIntegration: loggingIntegration
        )
    }
}

extension TracingWithLoggingIntegration {
    static func mockAny() -> TracingWithLoggingIntegration {
        return TracingWithLoggingIntegration(
            core: NOPDatadogCore(),
            service: .mockAny(),
            networkInfoEnabled: .mockAny()
        )
    }
}

extension ContextMessageReceiver {
    static func mockAny() -> ContextMessageReceiver {
        return ContextMessageReceiver(bundleWithRumEnabled: true)
    }
}
