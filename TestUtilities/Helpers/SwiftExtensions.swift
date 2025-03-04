/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import XCTest

/*
 Set of general extensions over standard types for writing more readable tests.
 Extensions using Datadog domain objects should be put in `DatadogExtensions.swift`.
*/

extension Optional {
    struct UnwrappingException: Error {}

    public func unwrapOrThrow(file: StaticString = #file, line: UInt = #line) throws -> Wrapped {
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
    public func secondsAgo(_ seconds: TimeInterval) -> Date {
        return addingTimeInterval(-seconds)
    }
}

extension TimeInterval {
    public init(fromNanoseconds nanoseconds: Int64) {
        self = TimeInterval(nanoseconds) / 1_000_000_000
    }
}

extension String {
    public var utf8Data: Data { data(using: .utf8)! }

    public func removingPrefix(_ prefix: String) -> String {
        if self.hasPrefix(prefix) {
            return String(self.dropFirst(prefix.count))
        } else {
            fatalError("`\(self)` has no prefix of `\(prefix)`")
        }
    }

    public func randomcased() -> String {
        return Bool.random() ? self.lowercased() : self.uppercased()
    }

    public static let uuidRegex = "^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$"

    public func matches(regex: String) -> Bool {
        range(of: regex, options: .regularExpression, range: nil, locale: nil) != nil
    }
}

extension Data {
    public var utf8String: String { String(data: self, encoding: .utf8)! }
}

extension InputStream {
    public func readAllBytes(expectedSize: Int) -> Data {
        var data = Data()

        open()

        let buffer: UnsafeMutablePointer<UInt8> = .allocate(capacity: expectedSize)
        while hasBytesAvailable {
            let bytesRead = self.read(buffer, maxLength: expectedSize)

            guard bytesRead >= 0 else {
                fatalError("Stream error occurred.")
            }

            if bytesRead == 0 {
                break
            }

            data.append(buffer, count: bytesRead)
        }

        buffer.deallocate()
        close()

        return data
    }
}

public extension URL {
    var absoluteStringWithoutQuery: String? {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.query = nil // drop query params
        return components?.url?.absoluteString
    }

    func queryItem(_ name: String) -> URLQueryItem? {
        let components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first { $0.name == name }
    }
}

extension URLRequest {
    public func removing(httpHeaderField: String) -> URLRequest {
        var request = self
        request.setValue(nil, forHTTPHeaderField: httpHeaderField)
        return request
    }

    public func dump() -> String {
        var headersDump: String = ""
        var bodyDump: String = ""

        if let allHTTPHeaderFields = self.allHTTPHeaderFields {
            if allHTTPHeaderFields.isEmpty {
                headersDump = "[]"
            } else {
                headersDump = "\n"
                allHTTPHeaderFields.forEach { field, value in
                    headersDump += "'\(field): \(value)'\n"
                }
            }
        } else {
            headersDump = "<nil>"
        }

        if let httpBody = self.httpBody {
            bodyDump = "'''"
            bodyDump += String(data: httpBody, encoding: .utf8) ?? "<invalid>"
            bodyDump += "\n'''"
        } else {
            bodyDump = "<nil>"
        }

        return """
        URLRequest:
        - url: '\(self.url?.absoluteString ?? "<nil>")'
        - headers:
        \(headersDump)
        - body:
        \(bodyDump)
        """
    }
}

extension URLSessionTask.State {
    public func dump() -> String {
        switch self {
        case .running: return "running"
        case .suspended: return "suspended"
        case .canceling: return "canceling"
        case .completed: return "completed"
        @unknown default: return "unknown"
        }
    }
}

/// Combines two arrays together, e.g. `["a", "b"].combined(with: [1, 2, 3])` gives
/// `[("a", 1), ("a", 2), ("a", 3), ("b", 1), ("b", 2), ("b", 3)]`.
public extension Array {
    /// Returns first element of the array which is of type `T`.
    /// - Parameters:
    ///   - type: the type of element to lookup
    ///   - unique: if `true` it will fail if there is more than one element of `T` in this array (`true` by default)
    /// - Returns: the first element of `T` in this array
    func firstElement<T>(of type: T.Type, unique: Bool = true, file: StaticString = #filePath, line: UInt = #line) -> T? {
        let all = compactMap { $0 as? T }
        if unique && all.count > 1 {
            XCTFail(
                """
                The array has more than one element of type \(T.self).
                Use `unique: false` if this is expected.
                """,
                file: file,
                line: line
            )
        }
        return all.first
    }
}

extension Dictionary where Key == Int, Value == String {
    public static func + (lhs: Self, rhs: Self) -> Self {
        lhs.merging(rhs) { _, new in new }
    }
}

public extension Result {
    /// Indicates whether the result is a success.
    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }

    /// Indicates whether the result is a failure.
    var isFailure: Bool {
        if case .failure = self {
            return true
        }
        return false
    }
}
