/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import TestUtilities
@testable import Datadog

extension TracingFeature {
    /// Mocks an instance of the feature that performs no writes to file system and does no uploads.
    static func mockAny() -> TracingFeature { .mockWith() }

    /// Mocks an instance of the feature that performs no writes to file system and does no uploads.
    static func mockWith(
        configuration: FeaturesConfiguration.Tracing = .mockAny(),
        messageReceiver: FeatureMessageReceiver = TracingMessageReceiver()
    ) -> TracingFeature {
        return TracingFeature(
            storage: .mockNoOp(),
            upload: .mockNoOp(),
            configuration: configuration,
            messageReceiver: messageReceiver
        )
    }
}

extension DatadogCoreProxy {
    func waitAndReturnSpanMatchers(file: StaticString = #file, line: UInt = #line) throws -> [SpanMatcher] {
        return try waitAndReturnEventsData(of: TracingFeature.self)
            .map { eventData in try SpanMatcher.fromJSONObjectData(eventData) }
    }
}

// MARK: - Span Mocks

extension DDSpanContext {
    static func mockAny() -> DDSpanContext {
        return mockWith()
    }

    static func mockWith(
        traceID: TracingUUID = .mockAny(),
        spanID: TracingUUID = .mockAny(),
        parentSpanID: TracingUUID? = .mockAny(),
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
        return BaggageItems(
            targetQueue: DispatchQueue(label: "com.datadoghq.baggage-items"),
            parentSpanItems: nil
        )
    }
}

extension DDSpan {
    static func mockAny(in core: DatadogCoreProtocol) -> DDSpan {
        return mockWith(core: core)
    }

    static func mockWith(
        tracer: Tracer,
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

extension TracingUUID {
    static func mockAny() -> TracingUUID {
        return TracingUUID(rawValue: .mockAny())
    }

    static func mock(_ rawValue: UInt64) -> TracingUUID {
        return TracingUUID(rawValue: rawValue)
    }
}

class RelativeTracingUUIDGenerator: TracingUUIDGenerator {
    private(set) var uuid: TracingUUID
    internal let count: UInt64
    private let queue = DispatchQueue(label: "queue-RelativeTracingUUIDGenerator-\(UUID().uuidString)")

    init(startingFrom uuid: TracingUUID, advancingByCount count: UInt64 = 1) {
        self.uuid = uuid
        self.count = count
    }

    func generateUnique() -> TracingUUID {
        return queue.sync {
            defer { uuid = uuid + count }
            return uuid
        }
    }
}

private func + (lhs: TracingUUID, rhs: UInt64) -> TracingUUID {
    return TracingUUID(rawValue: (UInt64(lhs.toString(.decimal)) ?? 0) + rhs)
}

extension SpanEvent: AnyMockable, RandomMockable {
    static func mockWith(
        traceID: TracingUUID = .mockAny(),
        spanID: TracingUUID = .mockAny(),
        parentID: TracingUUID? = .mockAny(),
        operationName: String = .mockAny(),
        serviceName: String = .mockAny(),
        resource: String = .mockAny(),
        startTime: Date = .mockAny(),
        duration: TimeInterval = .mockAny(),
        isError: Bool = .mockAny(),
        source: String = .mockAny(),
        origin: String? = nil,
        samplingRate: Float = 100,
        isKept: Bool = true,
        tracerVersion: String = .mockAny(),
        applicationVersion: String = .mockAny(),
        networkConnectionInfo: NetworkConnectionInfo? = .mockAny(),
        mobileCarrierInfo: CarrierInfo? = .mockAny(),
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
            userInfo: userInfo,
            tags: tags
        )
    }

    public static func mockAny() -> SpanEvent { .mockWith() }

    public static func mockRandom() -> SpanEvent {
        return SpanEvent(
            traceID: .init(rawValue: .mockRandom()),
            spanID: .init(rawValue: .mockRandom()),
            parentID: .init(rawValue: .mockRandom()),
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
            userInfo: .mockRandom(),
            tags: .mockRandom()
        )
    }
}

extension SpanEvent.UserInfo: AnyMockable, RandomMockable {
    static func mockWith(
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

// MARK: - Component Mocks

extension Tracer {
    static func mockAny(in core: DatadogCoreProtocol) -> Tracer {
        return mockWith(core: core)
    }

    static func mockWith(
        core: DatadogCoreProtocol,
        configuration: Configuration = .init(),
        spanEventMapper: SpanEventMapper? = nil,
        tracingUUIDGenerator: TracingUUIDGenerator = DefaultTracingUUIDGenerator(),
        dateProvider: DateProvider = SystemDateProvider(),
        rumIntegration: TracingWithRUMIntegration? = nil
    ) -> Tracer {
        return Tracer(
            core: core,
            configuration: configuration,
            spanEventMapper: spanEventMapper,
            tracingUUIDGenerator: tracingUUIDGenerator,
            dateProvider: dateProvider,
            rumIntegration: rumIntegration,
            loggingIntegration: .init(core: core, tracerConfiguration: configuration)
        )
    }
}

extension SpanEventBuilder {
    static func mockAny() -> SpanEventBuilder {
        return mockWith()
    }

    static func mockWith(
        serviceName: String = .mockAny(),
        sendNetworkInfo: Bool = false,
        eventsMapper: SpanEventMapper? = nil
    ) -> SpanEventBuilder {
        return SpanEventBuilder(
            serviceName: serviceName,
            sendNetworkInfo: sendNetworkInfo,
            eventsMapper: eventsMapper
        )
    }
}

extension TracingWithLoggingIntegration.Configuration: AnyMockable {
    public static func mockAny() -> TracingWithLoggingIntegration.Configuration {
        .init(
            service: .mockAny(),
            loggerName: .mockAny(),
            sendNetworkInfo: true
        )
    }
}
