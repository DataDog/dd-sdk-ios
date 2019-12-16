import XCTest
@testable import Datadog

class DatadogTests: XCTestCase {

    func testWhenCorrectEndpointAndClientTokenAreSet_itBuildsLogsUploadURL() throws {
        let datadog1 = try Datadog(
            logsEndpoint: "https://api.example.com/v1/logs/",
            clientToken: "abcdefghi"
        )
        XCTAssertEqual(datadog1.logsUploadURL, URL(string: "https://api.example.com/v1/logs/abcdefghi?ddsource=mobile")!)
        XCTAssertEqual(datadog1.logsUploadURL.query, "ddsource=mobile")
        
        let datadog2 = try Datadog(
            logsEndpoint: "https://api.example.com/v1/logs", // not normalized URL
            clientToken: "abcdefghi"
        )
        XCTAssertEqual(datadog2.logsUploadURL, URL(string: "https://api.example.com/v1/logs/abcdefghi?ddsource=mobile")!)
        XCTAssertEqual(datadog2.logsUploadURL.query, "ddsource=mobile")
    }
    
    func testWhenEmptyClientTokenIsNotSet_itThrows() {
        XCTAssertThrowsError(try Datadog(logsEndpoint: "https://api.example.com/v1/logs", clientToken: "")) { (error) in
            XCTAssertTrue((error as? DatadogInitializationException)?.description == "`clientToken` cannot be empty.")
        }
    }
    
    func testWhenLogsEndpointIsNotSet_itThrows() {
        XCTAssertThrowsError(try Datadog(logsEndpoint: "", clientToken: "abcdefghi")) { (error) in
            XCTAssertTrue((error as? DatadogInitializationException)?.description == "`logsEndpoint` cannot be empty.")
        }
    }
}
