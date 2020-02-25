import XCTest
@testable import HTTPServerMock

final class HTTPServerMockTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(HTTPServerMock().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
