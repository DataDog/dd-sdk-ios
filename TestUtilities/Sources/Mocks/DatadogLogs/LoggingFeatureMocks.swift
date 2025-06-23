/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

@testable import DatadogLogs

extension RemoteLogger.Configuration: AnyMockable {
    public static func mockAny() -> Self { .mockWith() }

    public static func mockWith(
        service: String? = "logger.tests",
        name: String? = "TestLogger",
        networkInfoEnabled: Bool = false,
        threshold: LogLevel = .info,
        eventMapper: LogEventMapper? = nil,
        sampler: Sampler = .mockKeepAll()
    ) -> Self {
        return .init(
            service: service,
            name: name,
            networkInfoEnabled: networkInfoEnabled,
            threshold: threshold,
            eventMapper: eventMapper,
            sampler: sampler
        )
    }
}

extension LogsFeature {
    /// Mocks an instance of the feature that performs no writes to file system and does no uploads.
    public static func mockAny() -> Self { .mockWith() }

    /// Mocks an instance of the feature that performs no writes to file system and does no uploads.
    static func mockWith(
        logEventMapper: LogEventMapper? = nil,
        requestBuilder: FeatureRequestBuilder = RequestBuilder(),
        messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver(),
        dateProvider: DateProvider = SystemDateProvider(),
        backtraceReporter: BacktraceReporting = BacktraceReporterMock(backtrace: nil)
    ) -> Self {
        return .init(
            logEventMapper: logEventMapper,
            requestBuilder: requestBuilder,
            messageReceiver: messageReceiver,
            dateProvider: dateProvider,
            backtraceReporter: backtraceReporter
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
        variant: String? = .mockAny(),
        device: Device = .mockAny(),
        os: OperatingSystem = .mockAny(),
        userInfo: UserInfo = .mockAny(),
        accountInfo: AccountInfo = .mockAny(),
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
            buildId: nil,
            variant: variant,
            dd: .init(device: .init(architecture: device.architecture ?? "")),
            device: device,
            os: os,
            userInfo: userInfo,
            accountInfo: accountInfo,
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
            variant: .mockRandom(),
            dd: .init(device: .init(architecture: .mockRandom())),
            device: .mockRandom(),
            os: .mockRandom(),
            userInfo: .mockRandom(),
            accountInfo: .mockRandom(),
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

extension LogEvent.Attributes: Equatable, AnyMockable, RandomMockable {
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

extension SynchronizedAttributes: AnyMockable {
    public static func mockAny() -> SynchronizedAttributes {
        return SynchronizedAttributes(attributes: [:])
    }
}

extension LogEventAttributes: RandomMockable {
    public static func mockRandom() -> LogEventAttributes {
        return .init(attributes: mockRandomAttributes())
    }
}
