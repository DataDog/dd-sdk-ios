import Foundation
import XCTest

/*
 Set of general extensions over standard types for writting more readable tests.
 Extensiosn using Datadog domain objects should be put in `DatadogExtensions.swift`.
*/

extension Optional {
    struct UnwrappingException: Error {}

    func unwrapOrThrow(file: StaticString = #file, line: UInt = #line) throws -> Wrapped {
        switch self {
        case .some(let unwrappedValue):
            return unwrappedValue
        case .none:
            XCTFail("Expected value, got `nil`.", file: file, line: line)
            throw UnwrappingException()
        }
    }
}

extension Date {
    func secondsAgo(_ seconds: TimeInterval) -> Date {
        return addingTimeInterval(-seconds)
    }

    func isNotOlderThan(seconds: TimeInterval) -> Bool {
        return Date().timeIntervalSince(self) <= seconds
    }
}

extension TimeZone {
    static var UTC: TimeZone {
        return TimeZone(abbreviation: "UTC")!
    }
}

extension Calendar {
    static var gregorian: Calendar {
        return Calendar(identifier: .gregorian)
    }
}

extension String {
    var utf8Data: Data { data(using: .utf8)! }

    func removingPrefix(_ prefix: String) -> String {
        if self.hasPrefix(prefix) {
            return String(self.dropFirst(prefix.count))
        } else {
            fatalError("`\(self)` has no prefix of `\(prefix)`")
        }
    }
}

extension Data {
    var utf8String: String { String(data: self, encoding: .utf8)! }
}
