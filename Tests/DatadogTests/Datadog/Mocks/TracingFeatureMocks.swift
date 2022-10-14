/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog

extension TracingFeature {
    /// Mocks feature instance which performs no writes and no uploads.
    static func mockNoOp(configuration: FeaturesConfiguration.Tracing = .mockAny()) -> TracingFeature {
        return TracingFeature(
            storage: .mockNoOp(),
            upload: .mockNoOp(),
            configuration: configuration,
            messageReceiver: NOPFeatureMessageReceiver()
        )
    }

    /// Mocks the feature instance which performs uploads to mocked `DataUploadWorker`.
    /// Use `TracingFeature.waitAndReturnSpanMatchers()` to inspect and assert recorded `Spans`.
    static func mockByRecordingSpanMatchers(
        configuration: FeaturesConfiguration.Tracing = .mockAny(),
        messageReceiver: FeatureMessageReceiver = TracingMessageReceiver()
    ) -> TracingFeature {
        // Mock storage with `InMemoryWriter`, used later for retrieving recorded events back:
        let interceptedStorage = FeatureStorage(
            writer: InMemoryWriter(),
            reader: NoOpFileReader(),
            arbitraryAuthorizedWriter: NoOpFileWriter(),
            dataOrchestrator: NoOpDataOrchestrator()
        )
        return TracingFeature(
            storage: interceptedStorage,
            upload: .mockNoOp(),
            configuration: configuration,
            messageReceiver: messageReceiver
        )
    }

    // MARK: - Expecting Spans Data

    func waitAndReturnSpanMatchers(count: UInt, file: StaticString = #file, line: UInt = #line) throws -> [SpanMatcher] {
        guard let inMemoryWriter = storage.writer as? InMemoryWriter else {
            preconditionFailure("Retrieving matchers requires that feature is mocked with `.mockByRecordingSpanMatchers()`")
        }
        return try inMemoryWriter.waitAndReturnEventsData(count: count, file: file, line: line)
            .map { eventData in try SpanMatcher.fromJSONObjectData(eventData) }
    }

    // swiftlint:disable:next function_default_parameter_at_end
    static func waitAndReturnSpanMatchers(in core: DatadogCoreProtocol = defaultDatadogCore, count: UInt, file: StaticString = #file, line: UInt = #line) throws -> [SpanMatcher] {
        guard let tracing = core.v1.feature(TracingFeature.self) else {
            preconditionFailure("TracingFeature is not registered in core")
        }

        return try tracing.waitAndReturnSpanMatchers(count: count, file: file, line: line)
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
            defer { uuid = TracingUUID(rawValue: uuid.rawValue + count) }
            return uuid
        }
    }
}

extension SpanEvent: EquatableInTests {}

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
            tracerVersion: tracerVersion,
            applicationVersion: applicationVersion,
            networkConnectionInfo: networkConnectionInfo,
            mobileCarrierInfo: mobileCarrierInfo,
            userInfo: userInfo,
            tags: tags
        )
    }

    static func mockAny() -> SpanEvent { .mockWith() }

    static func mockRandom() -> SpanEvent {
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

    static func mockAny() -> SpanEvent.UserInfo { .mockWith() }

    static func mockRandom() -> SpanEvent.UserInfo {
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
    static func mockAny() -> TracingWithLoggingIntegration.Configuration {
        .init(
            service: .mockAny(),
            loggerName: .mockAny(),
            sendNetworkInfo: true
        )
    }
}
