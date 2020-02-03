import Foundation
import XCTest
@testable import Datadog

struct LogMatcher {
    private static let dateFormatter = ISO8601DateFormatter()

    let json: [String: Any]

    func assertDate(matches datePredicate: (Date) -> Bool, file: StaticString = #file, line: UInt = #line) {
        guard let dateString = json[LogEncoder.StaticCodingKeys.date.rawValue] as? String else {
            XCTFail("Cannot decode date from log JSON: \(json).", file: file, line: line)
            return
        }
        guard let date = LogMatcher.dateFormatter.date(from: dateString) else {
            XCTFail("Date has invalid format: \(dateString).", file: file, line: line)
            return
        }
        XCTAssertTrue(datePredicate(date), file: file, line: line)
    }

    func assertServiceName(equals serviceName: String, file: StaticString = #file, line: UInt = #line) {
        assertJSONValue(forKey: LogEncoder.StaticCodingKeys.service.rawValue, equals: serviceName, file: file, line: line)
    }

    func assertStatus(equals status: String, file: StaticString = #file, line: UInt = #line) {
        assertJSONValue(forKey: LogEncoder.StaticCodingKeys.status.rawValue, equals: status, file: file, line: line)
    }

    func assertMessage(equals message: String, file: StaticString = #file, line: UInt = #line) {
        assertJSONValue(forKey: LogEncoder.StaticCodingKeys.message.rawValue, equals: message, file: file, line: line)
    }

    func assertAttributes(equal attributes: [String: Any], file: StaticString = #file, line: UInt = #line) {
        attributes.forEach { key, value in
            switch json[key] {
            case is String:
                XCTAssertEqual(json[key] as? String, value as? String, file: file, line: line)
            case is Int:
                XCTAssertEqual(json[key] as? Int, value as? Int, file: file, line: line)
            default:
                if json[key] == nil {
                    XCTFail("Expected `\(value)` but found `nil` for attribute `\(key)`", file: file, line: line)
                } else {
                    XCTFail("Attribute's value type: \(type(of: value)) is not supported by `LogMatcher`", file: file, line: line)
                }
            }
        }
    }

    func assertTags(equal tags: [String], file: StaticString = #file, line: UInt = #line) {
        guard let tagsString = json[LogEncoder.StaticCodingKeys.tags.rawValue] as? String else {
            XCTFail("Cannot decode date from log JSON: \(json).", file: file, line: line)
            return
        }

        let matcherTags = Set(tags)
        let logTags = Set(tagsString.split(separator: ",").map { String($0) })

        XCTAssertEqual(matcherTags, logTags, file: file, line: line)
    }

    private func assertJSONValue<T: Equatable>(forKey key: String, equals value: T, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(json[key] as? T, value, file: file, line: line)
    }
}

extension ServerSession where R == LogsRequest {
    func retrieveLogMatchers() throws -> [LogMatcher] {
        return try recordedRequests
            .flatMap { request in try request.getLogJSONs() }
            .map { logJSON in LogMatcher(json: logJSON) }
    }
}
