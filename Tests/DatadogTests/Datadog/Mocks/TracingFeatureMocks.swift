/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog

extension TracingFeature {
    /// Mocks feature instance which performs no writes and no uploads.
    static func mockNoOp() -> TracingFeature {
        return TracingFeature(
            storage: .mockNoOp(),
            upload: .mockNoOp(),
            configuration: .mockAny(),
            commonDependencies: .mockAny(),
            telemetry: nil
        )
    }

    /// Mocks the feature instance which performs uploads to `URLSession`.
    /// Use `ServerMock` to inspect and assert recorded `URLRequests`.
    static func mockWith(
        directory: Directory,
        configuration: FeaturesConfiguration.Tracing = .mockAny(),
        dependencies: FeaturesCommonDependencies = .mockAny(),
        telemetry: Telemetry? = nil
    ) -> TracingFeature {
        // Because in V2 Feature Storage and Upload are created by `DatadogCore`, here we ask
        // dummy V2 core instance to initialize the Feature. It is hacky, yet minimal way of
        // providing V1 stack for partial V2 architecture in tests.
        let v2Core = DatadogCore(
            rootDirectory: directory,
            configuration: configuration.common,
            dependencies: dependencies
        )
        v2Core.telemetry = telemetry

        let feature: TracingFeature = try! v2Core.create(
            storageConfiguration: createV2TracingStorageConfiguration(),
            uploadConfiguration: createV2TracingUploadConfiguration(v1Configuration: configuration),
            featureSpecificConfiguration: configuration
        )
        return feature
    }

    /// Mocks the feature instance which performs uploads to mocked `DataUploadWorker`.
    /// Use `TracingFeature.waitAndReturnSpanMatchers()` to inspect and assert recorded `Spans`.
    static func mockByRecordingSpanMatchers(
        directory: Directory,
        configuration: FeaturesConfiguration.Tracing = .mockAny(),
        dependencies: FeaturesCommonDependencies = .mockAny(),
        telemetry: Telemetry? = nil
    ) -> TracingFeature {
        // Get the full feature mock:
        let fullFeature: TracingFeature = .mockWith(
            directory: directory,
            configuration: configuration,
            dependencies: dependencies.replacing(
                dateProvider: SystemDateProvider() // replace date provider in mocked `Feature.Storage`
            )
        )
        let uploadWorker = DataUploadWorkerMock()
        let observedStorage = uploadWorker.observe(featureStorage: fullFeature.storage)
        // Replace by mocking the `FeatureUpload` and observing the `FeatureStorage`:
        let mockedUpload = FeatureUpload(uploader: uploadWorker)
        // Tear down the original upload
        fullFeature.upload.flushAndTearDown()
        return TracingFeature(
            storage: observedStorage,
            upload: mockedUpload,
            configuration: configuration,
            commonDependencies: dependencies,
            telemetry: telemetry
        )
    }

    // MARK: - Expecting Spans Data

    func waitAndReturnSpanMatchers(count: UInt, file: StaticString = #file, line: UInt = #line) throws -> [SpanMatcher] {
        guard let uploadWorker = upload.uploader as? DataUploadWorkerMock else {
            preconditionFailure("Retrieving matchers requires that feature is mocked with `.mockByRecordingSpanMatchers()`")
        }
        return try uploadWorker.waitAndReturnBatchedData(count: count, file: file, line: line)
            .flatMap { batchData in try SpanMatcher.fromNewlineSeparatedJSONObjectsData(batchData) }
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
    static func mockAny() -> DDSpan {
        return mockWith()
    }

    static func mockWith(
        tracer: Tracer = .mockAny(),
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
    static func mockAny() -> Tracer {
        return mockWith()
    }

    static func mockWith(
        spanBuilder: SpanEventBuilder = .mockAny(),
        spanOutput: SpanOutput = SpanOutputMock(),
        dateProvider: DateProvider = SystemDateProvider(),
        tracingUUIDGenerator: TracingUUIDGenerator = DefaultTracingUUIDGenerator(),
        globalTags: [String: Encodable]? = nil,
        rumContextIntegration: TracingWithRUMContextIntegration? = nil,
        loggingIntegration: TracingWithLoggingIntegration? = nil
    ) -> Tracer {
        return Tracer(
            spanBuilder: spanBuilder,
            spanOutput: spanOutput,
            dateProvider: dateProvider,
            tracingUUIDGenerator: tracingUUIDGenerator,
            globalTags: globalTags,
            rumContextIntegration: rumContextIntegration,
            loggingIntegration: loggingIntegration
        )
    }
}

extension SpanEventBuilder {
    static func mockAny() -> SpanEventBuilder {
        return mockWith()
    }

    static func mockWith(
        applicationVersion: String = .mockAny(),
        serviceName: String = .mockAny(),
        userInfoProvider: UserInfoProvider = .mockAny(),
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType = NetworkConnectionInfoProviderMock.mockAny(),
        carrierInfoProvider: CarrierInfoProviderType = CarrierInfoProviderMock.mockAny(),
        dateCorrector: DateCorrectorType = DateCorrectorMock(),
        source: String = .mockAny(),
        origin: String? = nil,
        sdkVersion: String = .mockAny(),
        eventsMapper: SpanEventMapper? = nil,
        telemetry: Telemetry? = nil
    ) -> SpanEventBuilder {
        return SpanEventBuilder(
            sdkVersion: sdkVersion,
            applicationVersion: applicationVersion,
            serviceName: serviceName,
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider,
            dateCorrector: dateCorrector,
            source: source,
            origin: origin,
            eventsMapper: eventsMapper,
            telemetry: telemetry
        )
    }
}

/// `SpanOutput` recording received spans.
class SpanOutputMock: SpanOutput {
    var onSpanRecorded: ((SpanEvent) -> Void)?

    var lastRecordedSpan: SpanEvent?
    var allRecordedSpans: [SpanEvent] = []

    func write(span: SpanEvent) {
        lastRecordedSpan = span
        allRecordedSpans.append(span)
        onSpanRecorded?(span)
    }
}
