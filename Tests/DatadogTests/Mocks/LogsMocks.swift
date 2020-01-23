import Foundation
@testable import Datadog

/*
A collection of mocks for Logs objects.
It follows the mocking conventions described in `FoundationMocks.swift`.
 */

extension Log {
    static func mockRandom() -> Log {
        return Log(
            date: .mockRandomInThePast(),
            status: .mockRandom(),
            message: .mockRandom(length: 20),
            service: "ios-sdk-unit-tests",
            attributes: [:]
        )
    }

    static func mockAnyWith(status: Log.Status) -> Log {
        return Log(
            date: .mockRandomInThePast(),
            status: status,
            message: .mockRandom(length: 20),
            service: "ios-sdk-unit-tests",
            attributes: [:]
        )
    }
}

extension Log.Status {
    static func mockRandom() -> Log.Status {
        let statuses: [Log.Status] = [.debug, .info, .notice, .warn, .error, .critical]
        return statuses.randomElement()!
    }

    static func mockAny() -> Log.Status {
        return .info
    }
}

extension EncodableValue {
    static func mockAny() -> EncodableValue {
        return EncodableValue(String.mockAny())
    }
}

extension LogBuilder {
    /// Mocks `LogBuilder` producing logs signed with given `date` and `serviceName`.
    static func mockUsing(date: Date, serviceName: String = "test-service") -> LogBuilder {
        let dateProvider = DateProviderMock()
        dateProvider.currentDates = [date]
        return LogBuilder(
            serviceName: serviceName,
            dateProvider: dateProvider
        )
    }
}
