/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import TestUtilities
import DatadogInternal

@testable import DatadogLogs
@testable import DatadogCore

extension DatadogCoreProxy {
    func waitAndReturnLogMatchers(file: StaticString = #file, line: UInt = #line) throws -> [LogMatcher] {
        return try waitAndReturnEventsData(ofFeature: LogsFeature.name)
            .map { data in try LogMatcher.fromJSONObjectData(data) }
    }
}

extension LogsFeature {
    /// Mocks an instance of the feature that performs no writes to file system and does no uploads.
    static func mockAny() -> Self { .mockWith() }

    /// Mocks an instance of the feature that performs no writes to file system and does no uploads.
    static func mockWith(
        logEventMapper: LogEventMapper? = nil,
        requestBuilder: FeatureRequestBuilder = RequestBuilder(),
        messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver(),
        dateProvider: DateProvider = SystemDateProvider()
    ) -> Self {
        return .init(
            logEventMapper: logEventMapper,
            requestBuilder: requestBuilder,
            messageReceiver: messageReceiver,
            dateProvider: dateProvider
        )
    }
}

extension LogMessageReceiver: AnyMockable {
    public static func mockAny() -> Self {
        .mockWith()
    }

    public static func mockWith(
        logEventMapper: LogEventMapper? = nil
    ) -> Self {
        .init(
            logEventMapper: logEventMapper
        )
    }
}

extension CrashLogReceiver: AnyMockable {
    public static func mockAny() -> Self {
        .mockWith()
    }

    public static func mockWith(
        dateProvider: DateProvider = SystemDateProvider()
    ) -> Self {
        .init(
            dateProvider: dateProvider
        )
    }
}

// MARK: - Log Mocks

extension LogLevel: AnyMockable, RandomMockable {
    public static func mockAny() -> LogLevel {
        return .debug
    }

    public static func mockRandom() -> LogLevel {
        return [
            LogLevel.debug,
            LogLevel.info,
            LogLevel.notice,
            LogLevel.warn,
            LogLevel.error,
            LogLevel.critical,
        ].randomElement()!
    }
}

extension LogEvent: AnyMockable, RandomMockable {
    public static func mockAny() -> LogEvent {
        return mockWith()
    }

    public static func mockWith(
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
        applicationBuildNumber: String = .mockAny(),
        buildId: String? = .mockAny(),
        dd: LogEvent.Dd = .mockAny(),
        os: LogEvent.OperatingSystem = .mockAny(),
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
            applicationBuildNumber: applicationBuildNumber,
            buildId: buildId,
            dd: dd,
            os: os,
            userInfo: userInfo,
            networkConnectionInfo: networkConnectionInfo,
            mobileCarrierInfo: mobileCarrierInfo,
            attributes: attributes,
            tags: tags
        )
    }

    public static func mockRandom() -> LogEvent {
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
            applicationBuildNumber: .mockRandom(),
            buildId: .mockRandom(),
            dd: .mockRandom(),
            os: .mockRandom(),
            userInfo: .mockRandom(),
            networkConnectionInfo: .mockRandom(),
            mobileCarrierInfo: .mockRandom(),
            attributes: .mockRandom(),
            tags: .mockRandom()
        )
    }
}

extension LogEvent.Status: RandomMockable {
    public static func mockAny() -> LogEvent.Status {
        return .info
    }

    public static func mockRandom() -> LogEvent.Status {
        return allCases.randomElement()!
    }
}

extension LogEvent.UserInfo: AnyMockable, RandomMockable {
    public static func mockAny() -> LogEvent.UserInfo {
        return mockEmpty()
    }

    public static func mockEmpty() -> LogEvent.UserInfo {
        return LogEvent.UserInfo(
            id: nil,
            name: nil,
            email: nil,
            extraInfo: [:]
        )
    }

    public static func mockRandom() -> LogEvent.UserInfo {
        return .init(
            id: .mockRandom(),
            name: .mockRandom(),
            email: .mockRandom(),
            extraInfo: mockRandomAttributes()
        )
    }
}

extension LogEvent.Dd: AnyMockable, RandomMockable {
    public static func mockAny() -> LogEvent.Dd {
        return LogEvent.Dd(
            device: .mockAny()
        )
    }

    public static func mockRandom() -> LogEvent.Dd {
        return LogEvent.Dd(
            device: .mockRandom()
        )
    }
}

extension LogEvent.OperatingSystem: AnyMockable, RandomMockable {
    public static func mockAny() -> Self {
        .init(
            name: .mockAny(),
            version: .mockAny(),
            build: .mockAny()
        )
    }

    public static func mockRandom() -> Self {
        .init(
            name: .mockRandom(),
            version: .mockRandom(),
            build: .mockRandom()
        )
    }
}

extension LogEvent.DeviceInfo: AnyMockable, RandomMockable {
    public static func mockAny() -> LogEvent.DeviceInfo {
        return LogEvent.DeviceInfo(
            brand: .mockAny(),
            name: .mockAny(),
            model: .mockAny(),
            architecture: .mockAny()
        )
    }

    public static func mockRandom() -> LogEvent.DeviceInfo {
        return LogEvent.DeviceInfo(
            brand: .mockRandom(),
            name: .mockRandom(),
            model: .mockRandom(),
            architecture: .mockRandom()
        )
    }
}

extension LogEvent.Error: RandomMockable {
    public static func mockRandom() -> Self {
        return .init(
            kind: .mockRandom(),
            message: .mockRandom(),
            stack: .mockRandom()
        )
    }
}

// MARK: - Component Mocks

extension LogEventBuilder: AnyMockable {
    public static func mockAny() -> LogEventBuilder {
        return mockWith()
    }

    public static func mockWith(
        service: String = .mockAny(),
        loggerName: String = .mockAny(),
        networkInfoEnabled: Bool = .mockAny(),
        eventMapper: LogEventMapper? = nil,
        deviceInfo: DeviceInfo = .mockAny()
    ) -> LogEventBuilder {
        return LogEventBuilder(
            service: service,
            loggerName: loggerName,
            networkInfoEnabled: networkInfoEnabled,
            eventMapper: eventMapper
        )
    }
}

extension LogEvent.Attributes: Equatable {
    public static func mockAny() -> LogEvent.Attributes {
        return mockWith()
    }

    public static func mockWith(
        userAttributes: [String: Encodable] = [:],
        internalAttributes: [String: Encodable]? = [:]
    ) -> LogEvent.Attributes {
        return LogEvent.Attributes(
            userAttributes: userAttributes,
            internalAttributes: internalAttributes
        )
    }

    public static func mockRandom() -> LogEvent.Attributes {
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
