import Foundation
@testable import Datadog

/*
A collection of mocks for Network objects.
It follows the mocking conventions described in `FoundationMocks.swift`.
 */

extension HTTPRequest {
    static func mockAny() -> HTTPRequest {
        return HTTPRequest(url: .mockAny(), headers: [:], method: "GET", body: Data())
    }
}

extension HTTPClient {
    static func mockDeliverySuccessWith(responseStatusCode: Int) -> HTTPClient {
        return HTTPClient(
            transport: URLSessionTransport(
                session: .mockDeliverySuccess(data: Data(), response: .mockResponseWith(statusCode: responseStatusCode))
            )
        )
    }
    
    static func mockDeliveryFailureWith(error: Error) -> HTTPClient {
        return HTTPClient(
            transport: URLSessionTransport(
                session: .mockDeliveryFailure(error: error)
            )
        )
    }
}
