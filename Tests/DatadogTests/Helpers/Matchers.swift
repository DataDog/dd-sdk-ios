import XCTest
@testable import Datadog

struct LogMatcher {
    private static let dateFormatter = ISO8601DateFormatter()

    let json: [String: Any]

    init(from json: [String: Any]) {
        self.json = json
    }

    init(from data: Data) throws {
        self.init(from: try data.toJSONObject())
    }

    // MARK: Full match

    func assertItFullyMatches(jsonString: String, file: StaticString = #file, line: UInt = #line) throws {
        let thisJSON = json as NSDictionary
        let theirJSON = try jsonString.utf8Data.toJSONObject() as NSDictionary

        XCTAssertEqual(thisJSON, theirJSON, file: file, line: line)
    }

    // MARK: Partial matches

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
        assertValue(forKey: LogEncoder.StaticCodingKeys.serviceName.rawValue, equals: serviceName, file: file, line: line)
    }

    func assertThreadName(equals threadName: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: LogEncoder.StaticCodingKeys.threadName.rawValue, equals: threadName, file: file, line: line)
    }

    func assertLoggerName(equals loggerName: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: LogEncoder.StaticCodingKeys.loggerName.rawValue, equals: loggerName, file: file, line: line)
    }

    func assertLoggerVersion(equals loggerVersion: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: LogEncoder.StaticCodingKeys.loggerVersion.rawValue, equals: loggerVersion, file: file, line: line)
    }

    func assertApplicationVersion(equals applicationVersion: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: LogEncoder.StaticCodingKeys.applicationVersion.rawValue, equals: applicationVersion, file: file, line: line)
    }

    func assertStatus(equals status: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: LogEncoder.StaticCodingKeys.status.rawValue, equals: status, file: file, line: line)
    }

    func assertMessage(equals message: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: LogEncoder.StaticCodingKeys.message.rawValue, equals: message, file: file, line: line)
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

    func assertValue<T: Equatable>(forKey key: String, equals value: T, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(json[key] as? T, value, file: file, line: line)
    }

    func assertNoValue(forKey key: String, file: StaticString = #file, line: UInt = #line) {
        XCTAssertNil(json[key], file: file, line: line)
    }
}
