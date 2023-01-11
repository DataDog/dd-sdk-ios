/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import TestUtilities
@testable import Datadog

extension LoggingFeature {
    /// Mocks the feature instance which performs no writes and no uploads.
    static func mockNoOp(configuration: FeaturesConfiguration.Logging = .mockAny()) -> LoggingFeature {
        return LoggingFeature(
            storage: .mockNoOp(),
            upload: .mockNoOp(),
            configuration: configuration,
            messageReceiver: NOPFeatureMessageReceiver()
        )
    }

    /// Mocks the feature instance which performs writes to `InMemoryWriter`.
    /// Use `LogFeature.waitAndReturnLogMatchers()` to inspect and assert recorded `Logs`.
    static func mockByRecordingLogMatchers(
        configuration: FeaturesConfiguration.Logging = .mockAny(),
        messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()
    ) -> LoggingFeature {
        // Mock storage with `InMemoryWriter`, used later for retrieving recorded events back:
        let interceptedStorage = FeatureStorage(
            writer: InMemoryWriter(),
            reader: NoOpFileReader(),
            arbitraryAuthorizedWriter: NoOpFileWriter(),
            dataOrchestrator: NoOpDataOrchestrator()
        )
        return LoggingFeature(
            storage: interceptedStorage,
            upload: .mockNoOp(),
            configuration: configuration,
            messageReceiver: messageReceiver
        )
    }

    // MARK: - Expecting Logs Data

    func waitAndReturnLogMatchers(count: UInt, file: StaticString = #file, line: UInt = #line) throws -> [LogMatcher] {
        guard let inMemoryWriter = storage.writer as? InMemoryWriter else {
            preconditionFailure("Retrieving matchers requires that feature is mocked with `.mockByRecordingLogMatchers()`")
        }
        return try inMemoryWriter.waitAndReturnEventsData(count: count, file: file, line: line)
            .map { eventData in try LogMatcher.fromJSONObjectData(eventData) }
    }

    // swiftlint:disable:next function_default_parameter_at_end
    static func waitAndReturnLogMatchers(in core: DatadogCoreProtocol = defaultDatadogCore, count: UInt, file: StaticString = #file, line: UInt = #line) throws -> [LogMatcher] {
        guard let logging = core.v1.feature(LoggingFeature.self) else {
            preconditionFailure("LoggingFeature is not registered in core")
        }

        return try logging.waitAndReturnLogMatchers(count: count, file: file, line: line)
    }
}

extension LogMessageReceiver: AnyMockable {
    static func mockAny() -> Self {
        .mockWith()
    }

    static func mockWith(
        logEventMapper: LogEventMapper? = nil
    ) -> Self {
        .init(
            logEventMapper: logEventMapper
        )
    }
}

extension CrashLogReceiver: AnyMockable {
    static func mockAny() -> Self {
        .mockWith()
    }

    static func mockWith(
        dateProvider: DateProvider = SystemDateProvider()
    ) -> Self {
        .init(
            dateProvider: dateProvider
        )
    }
}

// MARK: - Log Mocks

extension LogLevel: AnyMockable, RandomMockable {
    static func mockAny() -> LogLevel {
        return .debug
    }

    static func mockRandom() -> LogLevel {
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
        dd: LogEvent.Dd = .mockAny(),
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
            dd: dd,
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
            dd: .mockRandom(),
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

extension LogEvent.Dd: AnyMockable, RandomMockable {
    static func mockAny() -> LogEvent.Dd {
        return LogEvent.Dd(
            device: .mockAny()
        )
    }

    static func mockRandom() -> LogEvent.Dd {
        return LogEvent.Dd(
            device: .mockRandom()
        )
    }
}

extension LogEvent.DeviceInfo: AnyMockable, RandomMockable {
    static func mockAny() -> LogEvent.DeviceInfo {
        return LogEvent.DeviceInfo(
            architecture: .mockAny()
        )
    }

    static func mockRandom() -> LogEvent.DeviceInfo {
        return LogEvent.DeviceInfo(
            architecture: .mockRandom()
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

extension LogEventBuilder: AnyMockable {
    static func mockAny() -> LogEventBuilder {
        return mockWith()
    }

    static func mockWith(
        service: String = .mockAny(),
        loggerName: String = .mockAny(),
        sendNetworkInfo: Bool = .mockAny(),
        eventMapper: LogEventMapper? = nil,
        deviceInfo: DeviceInfo = .mockAny()
    ) -> LogEventBuilder {
        return LogEventBuilder(
            service: service,
            loggerName: loggerName,
            sendNetworkInfo: sendNetworkInfo,
            eventMapper: eventMapper
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
