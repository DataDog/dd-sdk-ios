import XCTest
@testable import Datadog

class URLSessionTransportTests: XCTestCase {

    func testWhenRequestIsDelivered_itReturnsResponse() {
        let expectation = self.expectation(description: "receive response")
        let sessionMock: URLSession = .mockDeliverySuccess(data: .mockAny(), response: .mockAny())
        
        let transport = URLSessionTransport(session: sessionMock)
        transport.send(request: .mockAny()) { (result) in
            switch result {
            case .response: expectation.fulfill()
            case .error: break
            }
        }
        
        waitForExpectations(timeout: 1, handler: nil)
    }
    
    func testWhenRequestIsNotDelivered_itReturnsError() {
        let expectation = self.expectation(description: "receive error")
        let sessionMock: URLSession = .mockDeliveryFailure(error: ErrorMock())
        
        let transport = URLSessionTransport(session: sessionMock)
        transport.send(request: .mockAny()) { (result) in
            switch result {
            case .response: break
            case .error: expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 1, handler: nil)
    }
}
