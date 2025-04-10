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
        isKept: Bool = true,
        tracerVersion: String = .mockAny(),
        applicationVersion: String = .mockAny(),
        networkConnectionInfo: NetworkConnectionInfo? = .mockAny(),
        mobileCarrierInfo: CarrierInfo? = .mockAny(),
        deviceInfo: SpanEvent.DeviceInfo = .mockAny(),
        osInfo: SpanEvent.OperatingSystemInfo = .mockAny(),
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
            isKept: isKept,
            tracerVersion: tracerVersion,
            applicationVersion: applicationVersion,
            networkConnectionInfo: networkConnectionInfo,
            mobileCarrierInfo: mobileCarrierInfo,
            deviceInfo: deviceInfo,
            osInfo: osInfo,
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
            isKept: .mockRandom(),
            tracerVersion: .mockRandom(),
            applicationVersion: .mockRandom(),
            networkConnectionInfo: .mockRandom(),
            mobileCarrierInfo: .mockRandom(),
            deviceInfo: .mockRandom(),
            osInfo: .mockRandom(),
            userInfo: .mockRandom(),
            tags: .mockRandom()
        )
    }
}

extension SpanEvent.DeviceInfo: AnyMockable, RandomMockable {
    public static func mockWith(
        brand: String = .mockAny(),
        name: String = .mockAny(),
        model: String = .mockAny(),
        architecture: String = .mockAny(),
        type: DeviceType = .mockAny()
    ) -> SpanEvent.DeviceInfo {
        return .init(
            brand: brand,
            name: name,
            model: model,
            architecture: architecture,
            type: type
        )
    }

    public static func mockAny() -> SpanEvent.DeviceInfo { mockWith() }
    public static func mockRandom() -> SpanEvent.DeviceInfo {
        return .init(
            brand: .mockRandom(),
            name: .mockRandom(),
            model: .mockRandom(),
            architecture: .mockRandom(),
            type: .mockRandom()
        )
    }
}

extension SpanEvent.DeviceInfo.DeviceType: AnyMockable, RandomMockable {
    public static func mockAny() -> SpanEvent.DeviceInfo.DeviceType { .mobile }
    public static func mockRandom() -> SpanEvent.DeviceInfo.DeviceType { [.mobile, .tablet, .tv, .other].randomElement()! }
}

extension SpanEvent.OperatingSystemInfo: AnyMockable, RandomMockable {
    public static func mockWith(
        name: String = .mockAny(),
        version: String = .mockAny(),
        build: String? = .mockAny(),
        versionMajor: String = .mockAny()
    ) -> SpanEvent.OperatingSystemInfo {
        return .init(
            name: name,
            version: version,
            build: build,
            versionMajor: versionMajor
        )
    }

    public static func mockAny() -> SpanEvent.OperatingSystemInfo { .mockWith() }

    public static func mockRandom() -> SpanEvent.OperatingSystemInfo {
        return .init(
            name: .mockRandom(),
            version: .mockRandom(),
            build: .mockRandom(),
            versionMajor: .mockRandom()
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
