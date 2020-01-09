import XCTest
@testable import Datadog

class DataUploadURLTests: XCTestCase {
    func testItBuildsValidURL() throws {
        let validURL1 = try DataUploadURL(endpointURL: "https://api.example.com/v1/endpoint", clientToken: "abc")
        XCTAssertEqual(validURL1.url, URL(string: "https://api.example.com/v1/endpoint/abc?ddsource=mobile"))

        let validURL2 = try DataUploadURL(endpointURL: "https://api.example.com/v1/endpoint/", clientToken: "abc")
        XCTAssertEqual(validURL2.url, URL(string: "https://api.example.com/v1/endpoint/abc?ddsource=mobile"))
    }

    func testWhenClientTokenIsInvalid_itThrowsProgrammerError() {
        XCTAssertThrowsError(try DataUploadURL(endpointURL: "https://api.example.com/v1/endpoint", clientToken: "")) { error in
            XCTAssertEqual((error as? ProgrammerError)?.description, "Datadog SDK usage error: `clientToken` cannot be empty.")
        }
    }

    func testWhenEndpointURLIsInvalid_itThrowsProgrammerError() {
        XCTAssertThrowsError(try DataUploadURL(endpointURL: "", clientToken: "abc")) { error in
            XCTAssertEqual((error as? ProgrammerError)?.description, "Datadog SDK usage error: `endpointURL` cannot be empty.")
        }
    }
}

class DataUploaderTests: XCTestCase {
    func testWhenDataIsSentWith200Code_itReturnsDataUploadStatus_success() {
        let uploader = DataUploader(url: .mockAny(), httpClient: .mockDeliverySuccessWith(responseStatusCode: 200))
        let status = uploader.upload(data: .mockAny())

        XCTAssertEqual(status, .success)
    }

    func testWhenDataIsSentWith300Code_itReturnsDataUploadStatus_redirection() {
        let uploader = DataUploader(url: .mockAny(), httpClient: .mockDeliverySuccessWith(responseStatusCode: 300))
        let status = uploader.upload(data: .mockAny())

        XCTAssertEqual(status, .redirection)
    }

    func testWhenDataIsSentWith400Code_itReturnsDataUploadStatus_clientError() {
        let uploader = DataUploader(url: .mockAny(), httpClient: .mockDeliverySuccessWith(responseStatusCode: 400))
        let status = uploader.upload(data: .mockAny())

        XCTAssertEqual(status, .clientError)
    }

    func testWhenDataIsSentWith500Code_itReturnsDataUploadStatus_serverError() {
        let uploader = DataUploader(url: .mockAny(), httpClient: .mockDeliverySuccessWith(responseStatusCode: 500))
        let status = uploader.upload(data: .mockAny())

        XCTAssertEqual(status, .serverError)
    }

    func testWhenDataIsNotSentDueToNetworkError_itReturnsDataUploadStatus_networkError() {
        let error = ErrorMock("network error")
        let uploader = DataUploader(url: .mockAny(), httpClient: .mockDeliveryFailureWith(error: error))
        let status = uploader.upload(data: .mockAny())

        XCTAssertEqual(status, .networkError)
    }

    func testWhenDataIsNotSentDueToUnknownStatusCode_itReturnsDataUploadStatus_unknown() {
        let uploader = DataUploader(url: .mockAny(), httpClient: .mockDeliverySuccessWith(responseStatusCode: -1))
        let status = uploader.upload(data: .mockAny())

        XCTAssertEqual(status, .unknown)
    }
}
