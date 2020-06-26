/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog

extension LoggingFeature {
    /// Mocks feature instance which performs no writes and no uploads.
    static func mockNoOp(temporaryDirectory: Directory) -> LoggingFeature {
        return LoggingFeature(
            directory: temporaryDirectory,
            configuration: .mockAny(),
            performance: .combining(storagePerformance: .noOp, uploadPerformance: .noOp),
            mobileDevice: .mockAny(),
            httpClient: .mockAny(),
            logsUploadURLProvider: .mockAny(),
            dateProvider: SystemDateProvider(),
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
        mobileDevice: MobileDevice = .mockWith(
            currentBatteryStatus: {
                // Mock full battery, so it doesn't rely on battery condition for the upload
                return BatteryStatus(state: .full, level: 1, isLowPowerModeEnabled: false)
            }
        ),
        logsUploadURLProvider: UploadURLProvider = .mockAny(),
        dateProvider: DateProvider = SystemDateProvider(),
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
    ) -> LoggingFeature {
        return LoggingFeature(
            directory: directory,
            configuration: configuration,
            performance: performance,
            mobileDevice: mobileDevice,
            httpClient: HTTPClient(session: server.urlSession),
            logsUploadURLProvider: logsUploadURLProvider,
            dateProvider: dateProvider,
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider
        )
    }
}

// MARK: - Log Mocks

extension Log {
    static func mockWith(
        date: Date = .mockAny(),
        status: Log.Status = .mockAny(),
        message: String = .mockAny(),
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
}

extension Log.Status {
    static func mockAny() -> Log.Status {
        return .info
    }
}

// MARK: - Component Mocks

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
        carrierInfoProvider: CarrierInfoProviderType = CarrierInfoProviderMock.mockAny()
    ) -> LogBuilder {
        return LogBuilder(
            applicationVersion: applicationVersion,
            environment: environment,
            serviceName: serviceName,
            loggerName: loggerName,
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider
        )
    }
}

extension LogAttributes: Equatable {
    static func mockAny() -> LogAttributes {
        return mockWith()
    }

    static func mockWith(
        userAttributes: [String: Encodable] = [:],
        internalAttributes: [String: Encodable]? = nil
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
    struct RecordedLog: Equatable {
        var level: LogLevel
        var message: String
        var date: Date
        var attributes = LogAttributes(userAttributes: [:], internalAttributes: nil)
        var tags: Set<String> = []
    }

    var recordedLog: RecordedLog? = nil

    func writeLogWith(level: LogLevel, message: String, date: Date, attributes: LogAttributes, tags: Set<String>) {
        recordedLog = RecordedLog(level: level, message: message, date: date, attributes: attributes, tags: tags)
    }
}
