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
            storage: .init(writer: NoOpFileWriter(), reader: NoOpFileReader()),
            upload: .init(uploader: NoOpDataUploadWorker()),
            configuration: .mockAny(),
            commonDependencies: .mockAny()
        )
    }

    /// Mocks the feature instance which performs uploads to `URLSession`.
    /// Use `ServerMock` to inspect and assert recorded `URLRequests`.
    static func mockWith(
        directories: FeatureDirectories,
        configuration: FeaturesConfiguration.Logging = .mockAny(),
        dependencies: FeaturesCommonDependencies = .mockAny()
    ) -> LoggingFeature {
        return LoggingFeature(directories: directories, configuration: configuration, commonDependencies: dependencies)
    }

    /// Mocks the feature instance which performs uploads to mocked `DataUploadWorker`.
    /// Use `LogFeature.waitAndReturnLogMatchers()` to inspect and assert recorded `Logs`.
    static func mockByRecordingLogMatchers(
        directories: FeatureDirectories,
        configuration: FeaturesConfiguration.Logging = .mockAny(),
        dependencies: FeaturesCommonDependencies = .mockAny()
    ) -> LoggingFeature {
        // Get the full feature mock:
        let fullFeature: LoggingFeature = .mockWith(
            directories: directories,
            configuration: configuration,
            dependencies: dependencies.replacing(
                dateProvider: SystemDateProvider() // replace date provider in mocked `Feature.Storage`
            )
        )
        let uploadWorker = DataUploadWorkerMock()
        let observedStorage = uploadWorker.observe(featureStorage: fullFeature.storage)
        // Replace by mocking the `FeatureUpload` and observing the `FatureStorage`:
        let mockedUpload = FeatureUpload(uploader: uploadWorker)
        return LoggingFeature(
            storage: observedStorage,
            upload: mockedUpload,
            configuration: configuration,
            commonDependencies: dependencies
        )
    }

    // MARK: - Expecting Logs Data

    static func waitAndReturnLogMatchers(count: UInt, file: StaticString = #file, line: UInt = #line) throws -> [LogMatcher] {
        guard let uploadWorker = LoggingFeature.instance?.upload.uploader as? DataUploadWorkerMock else {
            preconditionFailure("Retrieving matchers requires that feature is mocked with `.mockByRecordingLogMatchers()`")
        }
        return try uploadWorker.waitAndReturnBatchedData(count: count, file: file, line: line)
            .flatMap { batchData in try LogMatcher.fromArrayOfJSONObjectsData(batchData, file: file, line: line) }
    }
}

// MARK: - Log Mocks

extension Log: EquatableInTests {}

extension Log: RandomMockable {
    static func mockWith(
        date: Date = .mockAny(),
        status: Log.Status = .mockAny(),
        message: String = .mockAny(),
        error: DDError? = nil,
        serviceName: String = .mockAny(),
        environment: String = .mockAny(),
        loggerName: String = .mockAny(),
        loggerVersion: String = .mockAny(),
        threadName: String = .mockAny(),
        applicationVersion: String = .mockAny(),
        userInfo: UserInfo = .mockAny(),
        networkConnectionInfo: NetworkConnectionInfo = .mockAny(),
        mobileCarrierInfo: CarrierInfo? = .mockAny(),
        attributes: LogAttributes = .mockAny(),
        tags: [String]? = nil
    ) -> Log {
        return Log(
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

    static func mockRandom() -> Log {
        return Log(
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
            userInfo: .init(id: .mockRandom(), name: .mockRandom(), email: .mockRandom(), extraInfo: [:]), // TODO: RUMM-1050 use `.mockRandom()`
            networkConnectionInfo: .mockAny(), // TODO: RUMM-1050 use `.mockRandom()`
            mobileCarrierInfo: .mockAny(), // TODO: RUMM-1050 use `.mockRandom()`
            attributes: .mockAny(), // TODO: RUMM-1050 use `.mockRandom()`
            tags: nil // TODO: RUMM-1050 use `.mockRandom()`
        )
    }
}

extension Log.Status: RandomMockable {
    static func mockAny() -> Log.Status {
        return .info
    }

    static func mockRandom() -> Log.Status {
        return [.debug, .info, .notice, .warn, .error, .critical].randomElement()!
    }
}

// MARK: - Component Mocks

extension Logger {
    static func mockWith(
        logBuilder: LogBuilder = .mockAny(),
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

extension LogBuilder {
    static func mockAny() -> LogBuilder {
        return mockWith()
    }

    static func mockWith(
        applicationVersion: String = .mockAny(),
        environment: String = .mockAny(),
        serviceName: String = .mockAny(),
        loggerName: String = .mockAny(),
        userInfoProvider: UserInfoProvider = .mockAny(),
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType = NetworkConnectionInfoProviderMock.mockAny(),
        carrierInfoProvider: CarrierInfoProviderType = CarrierInfoProviderMock.mockAny(),
        dateCorrector: DateCorrectorType? = nil
    ) -> LogBuilder {
        return LogBuilder(
            applicationVersion: applicationVersion,
            environment: environment,
            serviceName: serviceName,
            loggerName: loggerName,
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider,
            dateCorrector: dateCorrector
        )
    }
}

extension LogAttributes: Equatable {
    static func mockAny() -> LogAttributes {
        return mockWith()
    }

    static func mockWith(
        userAttributes: [String: Encodable] = [:],
        internalAttributes: [String: Encodable]? = [:]
    ) -> LogAttributes {
        return LogAttributes(
            userAttributes: userAttributes,
            internalAttributes: internalAttributes
        )
    }

    public static func == (lhs: LogAttributes, rhs: LogAttributes) -> Bool {
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
    var recordedLog: Log?

    func write(log: Log) {
        recordedLog = log
    }
}
