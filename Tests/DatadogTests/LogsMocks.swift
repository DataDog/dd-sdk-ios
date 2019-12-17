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
            status: .info,
            message: .mockRandom(length: 20),
            service: "ios-sdk-unit-tests"
        )
    }
    
    static func mockAnyWith(status: Log.Status) -> Log {
        return Log(
            date: .mockRandomInThePast(),
            status: status,
            message: .mockRandom(length: 20),
            service: "ios-sdk-unit-tests"
        )
    }
}
