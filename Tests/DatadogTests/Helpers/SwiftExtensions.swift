/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import XCTest

/*
 Set of general extensions over standard types for writing more readable tests.
 Extensions using Datadog domain objects should be put in `DatadogExtensions.swift`.
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

    func randomcased() -> String {
        return Bool.random() ? self.lowercased() : self.uppercased()
    }

    static let uuidRegex = "^[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}$"

    func matches(regex: String) -> Bool {
        range(of: regex, options: .regularExpression, range: nil, locale: nil) != nil
    }
}

extension Data {
    var utf8String: String { String(data: self, encoding: .utf8)! }
}

extension InputStream {
    func readAllBytes(expectedSize: Int) -> Data {
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

extension URLRequest {
    func removing(httpHeaderField: String) -> URLRequest {
        var request = self
        request.setValue(nil, forHTTPHeaderField: httpHeaderField)
        return request
    }

    func dump() -> String {
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
    func dump() -> String {
        switch self {
        case .running: return "running"
        case .suspended: return "suspended"
        case .canceling: return "canceling"
        case .completed: return "completed"
        @unknown default: return "unknown"
        }
    }
}

extension URLSessionTask {
    func dump() -> String {
        func indent(string: String, by prefix: String) -> String {
            return string
                .split(separator: "\n")
                .map { prefix + $0 }
                .joined(separator: "\n")
        }

        return """
        URLSessionTask:
        - taskIdentifier: '\(self.taskIdentifier)'
        - taskDescription: '\(self.taskDescription ?? "<nil>")'
        - debugDescription: '\(self.debugDescription)'
        - state: '\(self.state.dump())'
        - originalRequest:
        \(indent(string: self.originalRequest?.dump() ?? "<nil>", by: "   "))
        - currentRequest:
        \(indent(string: self.currentRequest?.dump() ?? "<nil>", by: "   "))
        """
    }
}

/// Combines two arrays together, e.g. `["a", "b"].combined(with: [1, 2, 3])` gives
/// `[("a", 1), ("a", 2), ("a", 3), ("b", 1), ("b", 2), ("b", 3)]`.
extension Array {
    func combined<B>(with other: [B]) -> [(Element, B)] {
        return self.flatMap { a in other.map { b in (a, b) } }
    }
}
