import XCTest
@testable import Datadog

class HTTPClientTests: XCTestCase {

    func testWhenRequestIsDelivered_itReturnsHTTPResponse() {
        let expectation = self.expectation(description: "receive response")
        let succeedingTransport = URLSessionTransport(
            session: .mockDeliverySuccess(data: .mockAny(), response: .mockResponseWith(statusCode: 200))
        )
        let client = HTTPClient(transport: succeedingTransport)
        
        client.send(request: .mockAny()) { (result) in
            switch result {
            case .success(let httpResponse):
                XCTAssertEqual(httpResponse.code, 200)
                expectation.fulfill()
            case .failure:
                break
            }
        }
        
        waitForExpectations(timeout: 1, handler: nil)
    }
    
    func testWhenRequestIsNotDelivered_itReturnsHTTPRequestDeliveryError() {
        let expectation = self.expectation(description: "receive response")
        let succeedingTransport = URLSessionTransport(
            session: .mockDeliveryFailure(error: ErrorMock("no internet connection"))
        )
        let client = HTTPClient(transport: succeedingTransport)
        
        client.send(request: .mockAny()) { (result) in
            switch result {
            case .success:
                break
            case .failure(let error):
                XCTAssertEqual((error.details as? ErrorMock)?.description, "no internet connection")
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 1, handler: nil)
    }
}
