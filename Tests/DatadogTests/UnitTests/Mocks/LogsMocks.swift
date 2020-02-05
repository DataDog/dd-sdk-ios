import Foundation
@testable import Datadog

/*
A collection of mocks for Logs objects.
It follows the mocking conventions described in `FoundationMocks.swift`.
 */

extension Log {
    static func mockAnyWith(
        date: Date = .mockAny(),
        status: Log.Status = .mockAny(),
        message: String = .mockAny(),
        serviceName: String = .mockAny(),
        loggerName: String = .mockAny(),
        loggerVersion: String = .mockAny(),
        threadName: String = .mockAny(),
        attributes: [String: EncodableValue]? = nil,
        tags: [String]? = nil
    ) -> Log {
        return Log(
            date: date,
            status: status,
            message: message,
            serviceName: serviceName,
            loggerName: loggerName,
            loggerVersion: loggerVersion,
            threadName: threadName,
            attributes: attributes,
            tags: tags
        )
    }

    static func mockRandom() -> Log {
        return mockAnyWith(
            date: .mockRandomInThePast(),
            status: .mockRandom(),
            message: .mockRandom(length: 20),
            serviceName: .mockRandom(),
            loggerName: .mockRandom(),
            loggerVersion: .mockRandom(),
            threadName: .mockRandom()
        )
    }
}

extension Log.Status {
    static func mockAny() -> Log.Status {
        return .info
    }

    static func mockRandom() -> Log.Status {
        let statuses: [Log.Status] = [.debug, .info, .notice, .warn, .error, .critical]
        return statuses.randomElement()!
    }
}

extension EncodableValue {
    static func mockAny() -> EncodableValue {
        return EncodableValue(String.mockAny())
    }
}

extension LogBuilder {
    /// Mocks `LogBuilder` producing logs signed with given `date` and `serviceName`.
    static func mockUsing(date: Date, serviceName: String = "test-service", loggerName: String = "test-logger-name") -> LogBuilder {
        return LogBuilder(
            serviceName: serviceName,
            loggerName: loggerName,
            dateProvider: RelativeDateProvider(using: date)
        )
    }
}
