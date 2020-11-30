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
            storage: .init(writer: NoOpFileWriter(), reader: NoOpFileReader()),
            upload: .init(uploader: NoOpDataUploadWorker()),
            configuration: .mockAny(),
            commonDependencies: .mockAny(),
            loggingFeatureAdapter: nil,
            tracingUUIDGenerator: DefaultTracingUUIDGenerator()
        )
    }

    /// Mocks the feature instance which performs uploads to `URLSession`.
    /// Use `ServerMock` to inspect and assert recorded `URLRequests`.
    static func mockWith(
        directory: Directory,
        configuration: FeaturesConfiguration.Tracing = .mockAny(),
        dependencies: FeaturesCommonDependencies = .mockAny(),
        loggingFeature: LoggingFeature? = nil,
        tracingUUIDGenerator: TracingUUIDGenerator = DefaultTracingUUIDGenerator()
    ) -> TracingFeature {
        return TracingFeature(
            directory: directory,
            configuration: configuration,
            commonDependencies: dependencies,
            loggingFeatureAdapter: loggingFeature.flatMap { LoggingForTracingAdapter(loggingFeature: $0) },
            tracingUUIDGenerator: tracingUUIDGenerator
        )
    }

    /// Mocks the feature instance which performs uploads to mocked `DataUploadWorker`.
    /// Use `TracingFeature.waitAndReturnSpanMatchers()` to inspect and assert recorded `Spans`.
    static func mockByRecordingSpanMatchers(
        directory: Directory,
        configuration: FeaturesConfiguration.Tracing = .mockAny(),
        dependencies: FeaturesCommonDependencies = .mockAny(),
        loggingFeature: LoggingFeature? = nil,
        tracingUUIDGenerator: TracingUUIDGenerator = DefaultTracingUUIDGenerator()
    ) -> TracingFeature {
        // Get the full feature mock:
        let fullFeature: TracingFeature = .mockWith(
            directory: directory, dependencies: dependencies, loggingFeature: loggingFeature, tracingUUIDGenerator: tracingUUIDGenerator
        )
        let uploadWorker = DataUploadWorkerMock()
        let observedStorage = uploadWorker.observe(featureStorage: fullFeature.storage)
        // Replace by mocking the `FeatureUpload` and observing the `FatureStorage`:
        let mockedUpload = FeatureUpload(uploader: uploadWorker)
        return TracingFeature(
            storage: observedStorage,
            upload: mockedUpload,
            configuration: configuration,
            commonDependencies: dependencies,
            loggingFeatureAdapter: fullFeature.loggingFeatureAdapter,
            tracingUUIDGenerator: fullFeature.tracingUUIDGenerator
        )
    }

    // MARK: - Expecting Spans Data

    static func waitAndReturnSpanMatchers(count: UInt, file: StaticString = #file, line: UInt = #line) throws -> [SpanMatcher] {
        guard let uploadWorker = TracingFeature.instance?.upload.uploader as? DataUploadWorkerMock else {
            preconditionFailure("Retrieving matchers requires that feature is mocked with `.mockByRecordingSpanMatchers()`")
        }
        return try uploadWorker.waitAndReturnBatchedData(count: count, file: file, line: line)
            .flatMap { batchData in try SpanMatcher.fromNewlineSeparatedJSONObjectsData(batchData) }
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

// MARK: - Component Mocks

extension Tracer {
    static func mockAny() -> Tracer {
        return mockWith()
    }

    static func mockWith(
        spanOutput: SpanOutput = SpanOutputMock(),
        logOutput: LoggingForTracingAdapter.AdaptedLogOutput = .init(loggingOutput: LogOutputMock()),
        dateProvider: DateProvider = SystemDateProvider(),
        tracingUUIDGenerator: TracingUUIDGenerator = DefaultTracingUUIDGenerator(),
        globalTags: [String: Encodable]? = nil,
        rumContextIntegration: TracingWithRUMContextIntegration? = nil
    ) -> Tracer {
        return Tracer(
            spanOutput: spanOutput,
            logOutput: logOutput,
            dateProvider: dateProvider,
            tracingUUIDGenerator: tracingUUIDGenerator,
            globalTags: globalTags,
            rumContextIntegration: rumContextIntegration
        )
    }
}

extension SpanBuilder {
    static func mockAny() -> SpanBuilder {
        return mockWith()
    }

    static func mockWith(
        applicationVersion: String = .mockAny(),
        environment: String = .mockAny(),
        serviceName: String = .mockAny(),
        userInfoProvider: UserInfoProvider = .mockAny(),
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType = NetworkConnectionInfoProviderMock.mockAny(),
        carrierInfoProvider: CarrierInfoProviderType = CarrierInfoProviderMock.mockAny(),
        dateCorrection: DateCorrectionType = NTPDateCorrectionMock()
    ) -> SpanBuilder {
        return SpanBuilder(
            applicationVersion: applicationVersion,
            environment: environment,
            serviceName: serviceName,
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider,
            dateCorrection: dateCorrection
        )
    }
}

/// `SpanOutput` recording received spans.
class SpanOutputMock: SpanOutput {
    struct Recorded {
        let span: DDSpan
        let finishTime: Date
    }

    var onSpanRecorded: ((Recorded?) -> Void)?
    var recorded: Recorded? = nil {
        didSet { onSpanRecorded?(recorded) }
    }

    func write(ddspan: DDSpan, finishTime: Date) {
        recorded = Recorded(span: ddspan, finishTime: finishTime)
    }
}
