import XCTest
@testable import Datadog

class LogsUploaderTests: XCTestCase {
    func testWhenLogsAreSentWith200Code_itReportsLogsDeliveryStatus_success() throws {
        let expectation = self.expectation(description: "receive `LogsDeliveryStatus`")
        let uploader = LogsUploader(
            configuration: .mockAny(),
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
            configuration: .mockAny(),
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
            configuration: .mockAny(),
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
            configuration: .mockAny(),
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
            configuration: .mockAny(),
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
            configuration: .mockAny(),
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
