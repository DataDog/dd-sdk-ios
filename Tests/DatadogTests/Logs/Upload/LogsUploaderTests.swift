import XCTest
@testable import Datadog

class LogsUploaderTests: XCTestCase {
    func testWhenLogsAreSentWith200Code_itReportsLogsDeliveryStatus_success() throws {
        let expectation = self.expectation(description: "receive `LogsDeliveryStatus`")
        let uploader = LogsUploader(
            validURL: .mockAny(),
            httpClient: .mockDeliverySuccessWith(responseStatusCode: 200)
        )
        let logs: [Log] = [.mockRandom(), .mockRandom(), .mockRandom()]

        try uploader.upload(logs: logs) { status in
            XCTAssertEqual(status, LogsDeliveryStatus.success(logs: logs))
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1, handler: nil)
    }

    func testWhenLogsAreSentWith300Code_itReportsLogsDeliveryStatus_redirection() throws {
        let expectation = self.expectation(description: "receive `LogsDeliveryStatus`")
        let uploader = LogsUploader(
            validURL: .mockAny(),
            httpClient: .mockDeliverySuccessWith(responseStatusCode: 300)
        )
        let logs: [Log] = [.mockRandom(), .mockRandom(), .mockRandom()]

        try uploader.upload(logs: logs) { status in
            XCTAssertEqual(status, LogsDeliveryStatus.redirection(logs: logs))
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1, handler: nil)
    }

    func testWhenLogsAreSentWith400Code_itReportsLogsDeliveryStatus_redirection() throws {
        let expectation = self.expectation(description: "receive `LogsDeliveryStatus`")
        let uploader = LogsUploader(
            validURL: .mockAny(),
            httpClient: .mockDeliverySuccessWith(responseStatusCode: 400)
        )
        let logs: [Log] = [.mockRandom(), .mockRandom(), .mockRandom()]

        try uploader.upload(logs: logs) { status in
            XCTAssertEqual(status, LogsDeliveryStatus.clientError(logs: logs))
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1, handler: nil)
    }

    func testWhenLogsAreSentWith500Code_itReportsLogsDeliveryStatus_redirection() throws {
        let expectation = self.expectation(description: "receive `LogsDeliveryStatus`")
        let uploader = LogsUploader(
            validURL: .mockAny(),
            httpClient: .mockDeliverySuccessWith(responseStatusCode: 500)
        )
        let logs: [Log] = [.mockRandom(), .mockRandom(), .mockRandom()]

        try uploader.upload(logs: logs) { status in
            XCTAssertEqual(status, LogsDeliveryStatus.serverError(logs: logs))
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1, handler: nil)
    }

    func testWhenLogsAreNotSentDueToNetworkError_itReportsLogsDeliveryStatus_networkError() throws {
        let expectation = self.expectation(description: "receive `LogsDeliveryStatus`")
        let uploader = LogsUploader(
            validURL: .mockAny(),
            httpClient: .mockDeliveryFailureWith(error: ErrorMock("no network connection"))
        )
        let logs: [Log] = [.mockRandom(), .mockRandom(), .mockRandom()]

        try uploader.upload(logs: logs) { status in
            XCTAssertEqual(status, LogsDeliveryStatus.networkError(logs: logs))
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1, handler: nil)
    }

    func testWhenLogsAreSentWithUnknownStatusCode_itReportsLogsDeliveryStatus_unknown() throws {
        let expectation = self.expectation(description: "receive `LogsDeliveryStatus`")
        let uploader = LogsUploader(
            validURL: .mockAny(),
            httpClient: .mockDeliverySuccessWith(responseStatusCode: -1)
        )
        let logs: [Log] = [.mockRandom(), .mockRandom(), .mockRandom()]

        try uploader.upload(logs: logs) { status in
            XCTAssertEqual(status, LogsDeliveryStatus.unknown(logs: logs))
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1, handler: nil)
    }
}

class LogsUploaderValidURLTests: XCTestCase {
    func testItBuildsValidURLForLogsUpload() throws {
        let validURL1 = try LogsUploader.ValidURL(endpointURL: "https://api.example.com/v1/logs", clientToken: "abc")
        XCTAssertEqual(validURL1.url, URL(string: "https://api.example.com/v1/logs/abc?ddsource=mobile"))

        let validURL2 = try LogsUploader.ValidURL(endpointURL: "https://api.example.com/v1/logs/", clientToken: "abc")
        XCTAssertEqual(validURL2.url, URL(string: "https://api.example.com/v1/logs/abc?ddsource=mobile"))
    }

    func testWhenClientTokenIsInvalid_itThrowsProgrammerError() {
        XCTAssertThrowsError(try LogsUploader.ValidURL(endpointURL: "https://api.example.com/v1/logs", clientToken: "")) { error in
            XCTAssertTrue((error as? ProgrammerError)?.description == "`clientToken` cannot be empty.")
        }
    }

    func testWhenEndpointURLIsInvalid_itThrowsProgrammerError() {
        XCTAssertThrowsError(try LogsUploader.ValidURL(endpointURL: "", clientToken: "abc")) { error in
            XCTAssertTrue((error as? ProgrammerError)?.description == "`endpointURL` cannot be empty.")
        }
    }
}
