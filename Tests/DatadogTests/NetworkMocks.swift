import Foundation
@testable import Datadog

/*
A collection of mocks for Network objects.
It follows the mocking conventions described in `FoundationMocks.swift`.
 */

extension HTTPClient {
    static func mockDeliverySuccessWith(responseStatusCode: Int) -> HTTPClient {
        return HTTPClient(
            session: .mockDeliverySuccess(data: Data(), response: .mockResponseWith(statusCode: responseStatusCode))
        )
    }
    
    static func mockDeliveryFailureWith(error: Error) -> HTTPClient {
        return HTTPClient(
            session: .mockDeliveryFailure(error: error)
        )
    }
}
