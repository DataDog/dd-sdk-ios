/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog

extension LoggingFeature {
    /// Mocks the feature instance which performs no writes and no uploads.
    static func mockNoOp() -> LoggingFeature {
        return LoggingFeature(
            storage: .mockNoOp(),
            upload: .mockNoOp(),
            configuration: .mockAny(),
            commonDependencies: .mockAny(),
            telemetry: nil
        )
    }

    /// Mocks the feature instance which performs uploads to `URLSession`.
    /// Use `ServerMock` to inspect and assert recorded `URLRequests`.
    private static func mockWith(
        directory: Directory,
        featureConfiguration: FeaturesConfiguration.Logging = .mockAny(),
        telemetry: Telemetry? = nil
    ) -> LoggingFeature {
        // Because in V2 Feature Storage and Upload are created by `DatadogCore`, here we ask
        // dummy V2 core instance to initialize the Feature. It is hacky, yet minimal way of
        // providing V1 stack for partial V2 architecture in tests.
        let v2Core = DatadogCore(
            rootDirectory: directory,
            // Here we mock anything for `configuration` and `dependencies` of the dummy core instance.
            //
            // These ARE NOT used by the Feature to produce events. Instead, the Feature uses
            // context provided by standalone `DatadogCoreMock`.
            //
            // These ARE only used by the `FeatureStorage` and `FeatureUpload` to store and upload events.
            // Because storage and upload are responsibilities of core in V2, we don't test it
            // as part of Feature test.
            configuration: .mockAny(),
            dependencies: .mockAny()
        )
        v2Core.telemetry = telemetry

        let feature: LoggingFeature = try! v2Core.create(
            storageConfiguration: createV2LoggingStorageConfiguration(),
            uploadConfiguration: createV2LoggingUploadConfiguration(v1Configuration: featureConfiguration),
            featureSpecificConfiguration: featureConfiguration
        )
        return feature
    }

    /// Mocks the feature instance which performs uploads to mocked `DataUploadWorker`.
    /// Use `LogFeature.waitAndReturnLogMatchers()` to inspect and assert recorded `Logs`.
    static func mockByRecordingLogMatchers(
        directory: Directory,
        featureConfiguration: FeaturesConfiguration.Logging = .mockAny()
    ) -> LoggingFeature {
        // Get the full feature mock:
        let fullFeature: LoggingFeature = .mockWith(
            directory: directory,
            featureConfiguration: featureConfiguration
//            coreConfiguration: coreConfiguration,
//            coreDependencies: coreDependencies.replacing(
//                dateProvider: SystemDateProvider() // replace date provider in mocked `Feature.Storage`
//            )
        )
        let uploadWorker = DataUploadWorkerMock()
        let observedStorage = uploadWorker.observe(featureStorage: fullFeature.storage)
        // Replace by mocking the `FeatureUpload` and observing the `FeatureStorage`:
        let mockedUpload = FeatureUpload(uploader: uploadWorker)
        // Tear down the original upload
        fullFeature.upload.flushAndTearDown()

        return LoggingFeature(
            storage: observedStorage,
            upload: mockedUpload,
            configuration: fullFeature.configuration,
            // Here we mock anything for `commonDependencies`. This is only required by `V1FeatureInitializable` interface but not
            // used in this Feature implementation. It will be removed after we update the `V1FeatureInitializable` interface
            // for all other Features:
            commonDependencies: .mockAny(),
            telemetry: nil
        )
    }

    // MARK: - Expecting Logs Data

    func waitAndReturnLogMatchers(count: UInt, file: StaticString = #file, line: UInt = #line) throws -> [LogMatcher] {
        guard let uploadWorker = upload.uploader as? DataUploadWorkerMock else {
            preconditionFailure("Retrieving matchers requires that feature is mocked with `.mockByRecordingLogMatchers()`")
        }
        return try uploadWorker.waitAndReturnBatchedData(count: count, file: file, line: line)
            .flatMap { batchData in try LogMatcher.fromArrayOfJSONObjectsData(batchData, file: file, line: line) }
    }

    // swiftlint:disable:next function_default_parameter_at_end
    static func waitAndReturnLogMatchers(in core: DatadogCoreProtocol = defaultDatadogCore, count: UInt, file: StaticString = #file, line: UInt = #line) throws -> [LogMatcher] {
        guard let logging = core.v1.feature(LoggingFeature.self) else {
            preconditionFailure("LoggingFeature is not registered in core")
        }

        return try logging.waitAndReturnLogMatchers(count: count, file: file, line: line)
    }
}

// MARK: - Log Mocks

extension LogEvent: EquatableInTests {}

extension LogEvent: AnyMockable, RandomMockable {
    static func mockAny() -> LogEvent {
        return mockWith()
    }

    static func mockWith(
        date: Date = .mockAny(),
        status: LogEvent.Status = .mockAny(),
        message: String = .mockAny(),
        error: LogEvent.Error? = nil,
        serviceName: String = .mockAny(),
        environment: String = .mockAny(),
        loggerName: String = .mockAny(),
        loggerVersion: String = .mockAny(),
        threadName: String = .mockAny(),
        applicationVersion: String = .mockAny(),
        userInfo: UserInfo = .mockAny(),
        networkConnectionInfo: NetworkConnectionInfo = .mockAny(),
        mobileCarrierInfo: CarrierInfo? = .mockAny(),
        attributes: LogEvent.Attributes = .mockAny(),
        tags: [String]? = nil
    ) -> LogEvent {
        return LogEvent(
            date: date,
            status: status,
            message: message,
            error: error,
            serviceName: serviceName,
            environment: environment,
            loggerName: loggerName,
            loggerVersion: loggerVersion,
            threadName: threadName,
            applicationVersion: applicationVersion,
            userInfo: userInfo,
            networkConnectionInfo: networkConnectionInfo,
            mobileCarrierInfo: mobileCarrierInfo,
            attributes: attributes,
            tags: tags
        )
    }

    static func mockRandom() -> LogEvent {
        return LogEvent(
            date: .mockRandomInThePast(),
            status: .mockRandom(),
            message: .mockRandom(),
            error: .mockRandom(),
            serviceName: .mockRandom(),
            environment: .mockRandom(),
            loggerName: .mockRandom(),
            loggerVersion: .mockRandom(),
            threadName: .mockRandom(),
            applicationVersion: .mockRandom(),
            userInfo: .mockRandom(),
            networkConnectionInfo: .mockRandom(),
            mobileCarrierInfo: .mockRandom(),
            attributes: .mockRandom(),
            tags: .mockRandom()
        )
    }
}

extension LogEvent.Status: RandomMockable {
    static func mockAny() -> LogEvent.Status {
        return .info
    }

    static func mockRandom() -> LogEvent.Status {
        return allCases.randomElement()!
    }
}

extension LogEvent.UserInfo: AnyMockable, RandomMockable {
    static func mockAny() -> LogEvent.UserInfo {
        return mockEmpty()
    }

    static func mockEmpty() -> LogEvent.UserInfo {
        return LogEvent.UserInfo(
            id: nil,
            name: nil,
            email: nil,
            extraInfo: [:]
        )
    }

    static func mockRandom() -> LogEvent.UserInfo {
        return .init(
            id: .mockRandom(),
            name: .mockRandom(),
            email: .mockRandom(),
            extraInfo: mockRandomAttributes()
        )
    }
}

extension LogEvent.Error: RandomMockable {
    static func mockRandom() -> Self {
        return .init(
            kind: .mockRandom(),
            message: .mockRandom(),
            stack: .mockRandom()
        )
    }
}

// MARK: - Component Mocks

extension Logger {
    static func mockWith(
        logBuilder: LogEventBuilder = .mockAny(),
        logOutput: LogOutput = LogOutputMock(),
        dateProvider: DateProvider = SystemDateProvider(),
        identifier: String = .mockAny(),
        rumContextIntegration: LoggingWithRUMContextIntegration? = nil,
        activeSpanIntegration: LoggingWithActiveSpanIntegration? = nil
    ) -> Logger {
        return Logger(
            logBuilder: logBuilder,
            logOutput: logOutput,
            dateProvider: dateProvider,
            identifier: identifier,
            rumContextIntegration: rumContextIntegration,
            activeSpanIntegration: activeSpanIntegration
        )
    }
}

extension LogEventBuilder {
    static func mockAny() -> LogEventBuilder {
        return mockWith()
    }

    static func mockWith(
        sdkVersion: String = .mockAny(),
        applicationVersion: String = .mockAny(),
        environment: String = .mockAny(),
        serviceName: String = .mockAny(),
        loggerName: String = .mockAny(),
        userInfoProvider: UserInfoProvider = .mockAny(),
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType = NetworkConnectionInfoProviderMock.mockAny(),
        carrierInfoProvider: CarrierInfoProviderType = CarrierInfoProviderMock.mockAny(),
        dateCorrector: DateCorrectorType? = nil,
        logEventMapper: LogEventMapper? = nil
    ) -> LogEventBuilder {
        return LogEventBuilder(
            sdkVersion: sdkVersion,
            applicationVersion: applicationVersion,
            environment: environment,
            serviceName: serviceName,
            loggerName: loggerName,
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider,
            dateCorrector: dateCorrector,
            logEventMapper: logEventMapper
        )
    }
}

extension LogEvent.Attributes: Equatable {
    static func mockAny() -> LogEvent.Attributes {
        return mockWith()
    }

    static func mockWith(
        userAttributes: [String: Encodable] = [:],
        internalAttributes: [String: Encodable]? = [:]
    ) -> LogEvent.Attributes {
        return LogEvent.Attributes(
            userAttributes: userAttributes,
            internalAttributes: internalAttributes
        )
    }

    static func mockRandom() -> LogEvent.Attributes {
        return .init(
            userAttributes: mockRandomAttributes(),
            internalAttributes: mockRandomAttributes()
        )
    }

    public static func == (lhs: LogEvent.Attributes, rhs: LogEvent.Attributes) -> Bool {
        let lhsUserAttributesSorted = lhs.userAttributes.sorted { $0.key < $1.key }
        let rhsUserAttributesSorted = rhs.userAttributes.sorted { $0.key < $1.key }

        let lhsInternalAttributesSorted = lhs.internalAttributes?.sorted { $0.key < $1.key }
        let rhsInternalAttributesSorted = rhs.internalAttributes?.sorted { $0.key < $1.key }

        return String(describing: lhsUserAttributesSorted) == String(describing: rhsUserAttributesSorted)
            && String(describing: lhsInternalAttributesSorted) == String(describing: rhsInternalAttributesSorted)
    }
}

/// `LogOutput` recording received logs.
class LogOutputMock: LogOutput {
    var onLogRecorded: ((LogEvent) -> Void)?

    var recordedLog: LogEvent?
    var allRecordedLogs: [LogEvent] = []

    func write(log: LogEvent) {
        recordedLog = log
        allRecordedLogs.append(log)
        onLogRecorded?(log)
    }

    /// Returns newline-separated `String` description of all recorded logs.
    func dumpAllRecordedLogs() -> String {
        return allRecordedLogs
            .map { "- \($0)" }
            .joined(separator: "\n")
    }
}

/// `Telemtry` recording received telemetry.
class TelemetryMock: Telemetry, CustomStringConvertible {
    private(set) var debugs: [String] = []
    private(set) var errors: [(message: String, kind: String?, stack: String?)] = []
    private(set) var description: String = "Telemetry logs:"

    func debug(id: String, message: String) {
        debugs.append(message)
        description.append("\n- [debug] \(message)")
    }

    func error(id: String, message: String, kind: String?, stack: String?) {
        errors.append((message: message, kind: kind, stack: stack))
        description.append("\n - [error] \(message), kind: \(kind ?? "nil"), stack: \(stack ?? "nil")")
    }
}
