/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog

extension TracingFeature {
    /// Mocks feature instance which performs no writes and no uploads.
    static func mockNoOp(temporaryDirectory: Directory) -> TracingFeature {
        return TracingFeature(
            directory: temporaryDirectory,
            configuration: .mockAny(),
            performance: .combining(storagePerformance: .noOp, uploadPerformance: .noOp),
            loggingFeatureAdapter: nil,
            mobileDevice: .mockAny(),
            httpClient: .mockAny(),
            tracesUploadURLProvider: .mockAny(),
            dateProvider: SystemDateProvider(),
            tracingUUIDGenerator: DefaultTracingUUIDGenerator(),
            userInfoProvider: .mockAny(),
            networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockWith(
                networkConnectionInfo: .mockWith(
                    reachability: .no // so it doesn't meet the upload condition
                )
            ),
            carrierInfoProvider: CarrierInfoProviderMock.mockAny()
        )
    }

    /// Mocks feature instance which performs uploads to given `ServerMock` with performance optimized for fast delivery in unit tests.
    static func mockWorkingFeatureWith(
        server: ServerMock,
        directory: Directory,
        configuration: Datadog.ValidConfiguration = .mockAny(),
        performance: PerformancePreset = .combining(
            storagePerformance: .writeEachObjectToNewFileAndReadAllFiles,
            uploadPerformance: .veryQuick
        ),
        loggingFeature: LoggingFeature? = nil,
        mobileDevice: MobileDevice = .mockWith(
            currentBatteryStatus: {
                // Mock full battery, so it doesn't rely on battery condition for the upload
                return BatteryStatus(state: .full, level: 1, isLowPowerModeEnabled: false)
            }
        ),
        tracesUploadURLProvider: UploadURLProvider = .mockAny(),
        dateProvider: DateProvider = SystemDateProvider(),
        tracingUUIDGenerator: TracingUUIDGenerator = DefaultTracingUUIDGenerator(),
        userInfoProvider: UserInfoProvider = .mockAny(),
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType = NetworkConnectionInfoProviderMock.mockWith(
            networkConnectionInfo: .mockWith(
                reachability: .yes, // so it always meets the upload condition
                availableInterfaces: [.wifi],
                supportsIPv4: true,
                supportsIPv6: true,
                isExpensive: true,
                isConstrained: false // so it always meets the upload condition
            )
        ),
        carrierInfoProvider: CarrierInfoProviderType = CarrierInfoProviderMock.mockAny()
    ) -> TracingFeature {
        return TracingFeature(
            directory: directory,
            configuration: configuration,
            performance: performance,
            loggingFeatureAdapter: loggingFeature.flatMap { LoggingForTracingAdapter(loggingFeature: $0) },
            mobileDevice: mobileDevice,
            httpClient: HTTPClient(session: server.urlSession),
            tracesUploadURLProvider: tracesUploadURLProvider,
            dateProvider: dateProvider,
            tracingUUIDGenerator: tracingUUIDGenerator,
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider
        )
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
        tags: [String: Codable] = [:]
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
        tracingUUIDGenerator: TracingUUIDGenerator = DefaultTracingUUIDGenerator()
    ) -> Tracer {
        return Tracer(
            spanOutput: spanOutput,
            logOutput: logOutput,
            dateProvider: dateProvider,
            tracingUUIDGenerator: tracingUUIDGenerator
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
        carrierInfoProvider: CarrierInfoProviderType = CarrierInfoProviderMock.mockAny()
    ) -> SpanBuilder {
        return SpanBuilder(
            applicationVersion: applicationVersion,
            environment: environment,
            serviceName: serviceName,
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider
        )
    }
}

/// `SpanOutput` recording received spans.
class SpanOutputMock: SpanOutput {
    struct Recorded {
        let span: DDSpan
        let finishTime: Date
    }

    var recorded: Recorded? = nil

    func write(ddspan: DDSpan, finishTime: Date) {
        recorded = Recorded(span: ddspan, finishTime: finishTime)
    }
}
