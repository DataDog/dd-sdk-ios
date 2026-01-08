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
        samplingDecision: SamplingDecision = .mockAny()
    ) -> DDSpanContext {
        return DDSpanContext(
            traceID: traceID,
            spanID: spanID,
            parentSpanID: parentSpanID,
            baggageItems: baggageItems,
            sampleRate: sampleRate,
            samplingDecision: samplingDecision
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

    public static func mockWith(
        featureScope: FeatureScope,
        localTraceSampler: Sampler = .mockKeepAll(),
        tags: [String: Encodable] = [:],
        traceIDGenerator: TraceIDGenerator = DefaultTraceIDGenerator(),
        spanIDGenerator: SpanIDGenerator = DefaultSpanIDGenerator(),
        dateProvider: DateProvider = SystemDateProvider(),
        spanEventBuilder: SpanEventBuilder = .mockAny(),
        loggingIntegration: TracingWithLoggingIntegration = .mockAny()
    ) -> DatadogTracer {
        return DatadogTracer(
            featureScope: featureScope,
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
        let builder = SpanEventBuilder(
            service: service,
            networkInfoEnabled: networkInfoEnabled,
            eventsMapper: eventsMapper,
            bundleWithRUM: bundleWithRUM,
            telemetry: telemetry
        )
        builder.attributesEncoder.outputFormatting = [.sortedKeys] // to ensure stable order of JSON keys among OS versions
        return builder
    }
}

extension SpanEvent: AnyMockable, RandomMockable {
    public static func mockWith(
        traceID: TraceID = .mockAny(),
        spanID: SpanID = .mockAny(),
        parentID: SpanID? = .mockAny(),
        operationName: String = .mockAny(),
        serviceName: String = .mockAny(),
        resource: String = .mockAny(),
        startTime: Date = .mockAny(),
        duration: TimeInterval = .mockAny(),
        isError: Bool = .mockAny(),
        source: String = .mockAny(),
        origin: String? = nil,
        samplingRate: SampleRate = .maxSampleRate,
        samplingPriority: SamplingPriority = .mockAny(),
        samplingDecisionMaker: SamplingMechanismType = .mockAny(),
        tracerVersion: String = .mockAny(),
        applicationVersion: String = .mockAny(),
        networkConnectionInfo: NetworkConnectionInfo? = .mockAny(),
        mobileCarrierInfo: CarrierInfo? = .mockAny(),
        device: Device = .mockAny(),
        os: OperatingSystem = .mockAny(),
        userInfo: SpanEvent.UserInfo = .mockAny(),
        tags: [String: String] = [:]
    ) -> SpanEvent {
        return SpanEvent(
            traceID: traceID,
            spanID: spanID,
            parentID: parentID,
            operationName: operationName,
            serviceName: serviceName,
            resource: resource,
            startTime: startTime,
            duration: duration,
            isError: isError,
            source: source,
            origin: origin,
            samplingRate: samplingRate,
            samplingPriority: samplingPriority,
            samplingDecisionMaker: samplingDecisionMaker,
            tracerVersion: tracerVersion,
            applicationVersion: applicationVersion,
            networkConnectionInfo: networkConnectionInfo,
            mobileCarrierInfo: mobileCarrierInfo,
            device: device,
            os: os,
            userInfo: userInfo,
            tags: tags
        )
    }

    public static func mockAny() -> SpanEvent { .mockWith() }

    public static func mockRandom() -> SpanEvent {
        return SpanEvent(
            traceID: .mock(.mockRandom(), .mockRandom()),
            spanID: .mock(.mockRandom()),
            parentID: .mock(.mockRandom()),
            operationName: .mockRandom(),
            serviceName: .mockRandom(),
            resource: .mockRandom(),
            startTime: .mockRandomInThePast(),
            duration: .mockRandom(),
            isError: .random(),
            source: .mockRandom(),
            origin: .mockRandom(),
            samplingRate: .mockRandom(),
            samplingPriority: .mockRandom(),
            samplingDecisionMaker: .mockRandom(),
            tracerVersion: .mockRandom(),
            applicationVersion: .mockRandom(),
            networkConnectionInfo: .mockRandom(),
            mobileCarrierInfo: .mockRandom(),
            device: .mockRandom(),
            os: .mockRandom(),
            userInfo: .mockRandom(),
            tags: .mockRandom()
        )
    }
}

extension SpanEvent.UserInfo: AnyMockable, RandomMockable {
    public static func mockWith(
        id: String? = .mockAny(),
        name: String? = .mockAny(),
        email: String? = .mockAny(),
        extraInfo: [String: String] = [:]
    ) -> SpanEvent.UserInfo {
        return SpanEvent.UserInfo(
            id: id,
            name: name,
            email: email,
            extraInfo: extraInfo
        )
    }

    public static func mockAny() -> SpanEvent.UserInfo { .mockWith() }

    public static func mockRandom() -> SpanEvent.UserInfo {
        return SpanEvent.UserInfo(
            id: .mockRandom(),
            name: .mockRandom(),
            email: .mockRandom(),
            extraInfo: .mockRandom()
        )
    }
}

extension SpanEvent.AccountInfo: AnyMockable, RandomMockable {
    public static func mockWith(
        id: String = .mockAny(),
        name: String? = .mockAny(),
        extraInfo: [String: String] = [:]
    ) -> Self {
        return .init(
            id: id,
            name: name,
            extraInfo: extraInfo
        )
    }

    public static func mockAny() -> Self { .mockWith() }

    public static func mockRandom() -> Self {
        return .init(
            id: .mockRandom(),
            name: .mockRandom(),
            extraInfo: .mockRandom()
        )
    }
}

extension SamplingDecision: AnyMockable, RandomMockable {
    struct MockSampler: Sampling {
        let decision: Bool

        var samplingRate: SampleRate { 50 }

        func sample() -> Bool { decision }
    }

    public static func mockAny() -> SamplingDecision {
        SamplingDecision(sampling: MockSampler(decision: false))
    }

    public static func mockRandom() -> DatadogTrace.SamplingDecision {
        let randomPriority = (-1...2).randomElement()

        switch randomPriority {
        case -1:
            var decision = SamplingDecision(sampling: MockSampler(decision: true))
            decision.addManualDropOverride()
            return decision
        case 0:
            return SamplingDecision(sampling: MockSampler(decision: false))
        case 1:
            return SamplingDecision(sampling: MockSampler(decision: true))
        case 2:
            var decision = SamplingDecision(sampling: MockSampler(decision: true))
            decision.addManualKeepOverride()
            return decision
        default:
            fatalError()
        }
    }

    public static func autoKept() -> SamplingDecision {
        SamplingDecision(sampling: MockSampler(decision: true))
    }
}

extension SamplingPriority: AnyMockable, RandomMockable {
    public static func mockAny() -> SamplingPriority {
        .autoKeep
    }

    public static func mockRandom() -> SamplingPriority {
        [SamplingPriority.manualDrop, .autoDrop, .autoKeep, .manualKeep].randomElement()!
    }
}

extension SamplingMechanismType: AnyMockable, RandomMockable {
    public static func mockAny() -> SamplingMechanismType {
        .agentRate
    }

    public static func mockRandom() -> SamplingMechanismType {
        [SamplingMechanismType.fallback, .agentRate, .manual].randomElement()!
    }
}
