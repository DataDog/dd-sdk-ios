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
            status: "INFO",
            message: .mockRandom(length: 20),
            service: "ios-sdk-unit-tests"
        )
    }
}
