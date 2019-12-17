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
    
    func testItEncodesDifferentLogStatues() throws {
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
    
    // MARK: - custom matchers
    
    private func assertThat(serializedLogData: Data, fullyMatches jsonString: String, file: StaticString = #file, line: UInt = #line) {
        guard let jsonStringData = jsonString.data(using: .utf8) else {
            XCTFail("Cannot encode data from given json string.", file: file, line: line)
            return
        }

        guard let jsonObjectFromSerializedData = try? JSONSerialization.jsonObject(with: serializedLogData, options: []) as? NSArray else {
            XCTFail("Cannot decode JSON object from given `serializedLogData`.", file: file, line: line)
            return
        }
        guard let jsonObjectFromJSONString = try? JSONSerialization.jsonObject(with: jsonStringData, options: []) as? NSArray else {
            XCTFail("Cannot encode JSON object from given `jsonString`.", file: file, line: line)
            return
        }
        
        XCTAssertEqual(jsonObjectFromSerializedData, jsonObjectFromJSONString, file: file, line: line)
    }
    
    private func assertThat<T: Equatable>(serializedLogData: Data, matchesValue value: T, onKeyPath keyPath: String, file: StaticString = #file, line: UInt = #line) {
        guard let jsonObjectFromSerializedData = try? JSONSerialization.jsonObject(with: serializedLogData, options: []) as? NSArray else {
            XCTFail("Cannot decode JSON object from given `serializedLogData`.", file: file, line: line)
            return
        }
        
        guard let jsonObjectValue = jsonObjectFromSerializedData.value(forKeyPath: keyPath) as? T else {
            XCTFail("Cannot access or cast value of type \(T.self) on key path \(keyPath).", file: file, line: line)
            return
        }
        
        XCTAssertEqual(jsonObjectValue, value, file: file, line: line)
    }
}
