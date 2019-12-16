import XCTest
@testable import Datadog

class LogsUploadRequestEncoderTests: XCTestCase {

    private let logsUploadURL = URL(string: "https://api.example.com/v1/logs/abcdefghijklm")!
    
    func testItEncodesRequestData() throws {
        let encoder = LogsUploadRequestEncoder(uploadURL: logsUploadURL)
        
        let log1 = Log(date: .mockRandomInThePast(), status: "INFO", message: .mockRandom(), service: "service-name")
        let log2 = Log(date: .mockRandomInThePast(), status: "INFO", message: .mockRandom(), service: "service-name")
        let log3 = Log(date: .mockRandomInThePast(), status: "INFO", message: .mockRandom(), service: "service-name")
        
        let request = try encoder.encodeRequest(with: [log1, log2, log3])
        
        XCTAssertEqual(request.url.absoluteString, logsUploadURL.absoluteString)
        XCTAssertEqual(request.headers, ["Content-Type": "application/json"])
        XCTAssertEqual(request.method, "POST")
        XCTAssertGreaterThan(request.body.count, 0)
    }

    func testItEncodesDatesWithISO8601standard() throws {
        let encoder = LogsUploadRequestEncoder(uploadURL: logsUploadURL)
        let december15th2019At10AMUTC: Date = .mockSpecificUTCGregorianDate(year: 2019, month: 12, day: 15, hour: 10)
        let log = Log(date: december15th2019At10AMUTC, status: "INFO", message: .mockRandom(), service: "service-name")
        
        let encodedLogData = try encoder.encodeRequest(with: [log]).body
        let encodedLogJSONString = String(data: encodedLogData, encoding: .utf8) ?? ""
        
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601
        
        XCTAssertEqual(try jsonDecoder.decode([Log].self, from: encodedLogData), [log])
        XCTAssertTrue(encodedLogJSONString.contains("\"date\":\"2019-12-15T10:00:00Z\""))
    }
}
