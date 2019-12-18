import XCTest
@testable import Datadog

class LogsUploadRequestEncoderTests: XCTestCase {
    private let logsUploadURL = URL(string: "https://api.example.com/v1/logs/abcdefghijklm")!

    func testItEncodesRequestMetadata() throws {
        let encoder = LogsUploadRequestEncoder(uploadURL: logsUploadURL)
        let request = try encoder.encodeRequest(with: [Log.mockRandom()])

        XCTAssertEqual(request.url?.absoluteString, logsUploadURL.absoluteString)
        XCTAssertEqual(request.allHTTPHeaderFields, ["Content-Type": "application/json"])
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertGreaterThan(request.httpBody?.count ?? .min, 0)
    }

    // MARK: - `Log` tests

    func testItEncodesHTTPBodyAsJSONArray() throws {
        let json = """
        [
          {
            "status" : "INFO",
            "message" : "some message",
            "service" : "service-name",
            "date" : "2019-12-15T10:00:00Z"
          }
        ]
        """
        let logs = [
            Log(
                date: .mockDecember15th2019At10AMUTC(),
                status: .info,
                message: "some message",
                service: "service-name"
            )
        ]

        let encoder = LogsUploadRequestEncoder(uploadURL: .mockAny())
        let requestBody = try encoder.encodeRequest(with: logs).httpBody ?? Data()

        assertThat(serializedLogData: requestBody, fullyMatches: json)
    }

    func testItEncodesDifferentLogStatuses() throws {
        let logs: [Log] = [
            .mockAnyWith(status: .debug),
            .mockAnyWith(status: .info),
            .mockAnyWith(status: .notice),
            .mockAnyWith(status: .warn),
            .mockAnyWith(status: .error),
            .mockAnyWith(status: .critical),
        ]

        let encoder = LogsUploadRequestEncoder(uploadURL: .mockAny())
        let requestBody = try encoder.encodeRequest(with: logs).httpBody ?? Data()

        assertThat(
            serializedLogData: requestBody,
            matchesValue: ["DEBUG", "INFO", "NOTICE", "WARN", "ERROR", "CRITICAL"],
            onKeyPath: "@unionOfObjects.status"
        )
    }
}
