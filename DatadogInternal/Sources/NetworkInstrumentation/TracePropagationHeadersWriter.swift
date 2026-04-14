/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Write interface for a custom carrier
public protocol TracePropagationHeadersWriter {
    var traceHeaderFields: [String: String] { get }

    var traceHeaders: TraceHeaders { get }

    func write(traceContext: TraceContext)
}

extension TracePropagationHeadersWriter {
    public var traceHeaderFields: [String: String] {
        traceHeaders.headers.mapValues { $0.description }
    }
}

public struct TraceHeaders: ExpressibleByDictionaryLiteral {
    public typealias Key = String

    public typealias Value = TracePropagationHeaderValue

    public static func merged(_ elements: [TraceHeaders]) -> TraceHeaders {
        elements.reduce([:]) { partialResult, element in
            partialResult.merged(with: element)
        }
    }

    public init(dictionaryLiteral elements: (String, TracePropagationHeaderValue)...) {
        self.headers = Dictionary(elements, uniquingKeysWith: { lhs, rhs in rhs })
    }

    init(headers: [String: TracePropagationHeaderValue]) {
        self.headers = headers
    }

    public var headers: [String: TracePropagationHeaderValue]

    func merged(with other: TraceHeaders) -> TraceHeaders {
        .init(
            headers: headers.merging(other.headers) { lhs, rhs in
                lhs.merged(with: rhs)
            }
        )
    }

    public func filtered(by request: URLRequest) -> TraceHeaders {
        return TraceHeaders(
            headers: headers.filter { key, _ in
                request.value(forHTTPHeaderField: key) == nil
            }
        )
    }

    public var isEmpty: Bool {
        headers.isEmpty
    }

    public subscript(key: String) -> TracePropagationHeaderValue? {
        get {
            return headers[key]
        }
        set {
            headers[key] = newValue
        }
    }

    public subscript(string key: String) -> String? {
        get {
            return headers[key]?.description
        }
    }
}

public struct TracePropagationKeyValuePairsHeaderValue: CustomStringConvertible {
    let values: [String: String]
    let keyValueSeparator: String
    let keyValuePairSeparator: String

    init(values: [String : String], keyValueSeparator: String, keyValuePairSeparator: String) {
        self.values = values
        self.keyValueSeparator = keyValueSeparator
        self.keyValuePairSeparator = keyValuePairSeparator
    }

    public var description: String {
        values
            .sorted { lhs, rhs in lhs.key < rhs.key }
            .map { pair in "\(pair.key)\(keyValueSeparator)\(pair.value)" }
            .joined(separator: keyValuePairSeparator)
    }

    func merged(with other: TracePropagationKeyValuePairsHeaderValue) -> TracePropagationKeyValuePairsHeaderValue {
        .init(
            values: values.merging(other.values, uniquingKeysWith: { lhs, rhs in lhs }),
            keyValueSeparator: keyValueSeparator,
            keyValuePairSeparator: keyValuePairSeparator
        )
    }
}

public enum TracePropagationHeaderValue: CustomStringConvertible {
    case string(String)
    // Ideally this should be an ordered dictionary, but for the sake of not
    // adding a 3rd party dependency, we do it manually.
    case keyValueList(TracePropagationKeyValuePairsHeaderValue)

    public var description: String {
        switch self {
        case .string(let string):
            string.description
        case .keyValueList(let tracePropagationKeyValuePairsHeaderValue):
            tracePropagationKeyValuePairsHeaderValue.description
        }
    }

    func merged(with other: TracePropagationHeaderValue) -> TracePropagationHeaderValue {
        switch (self, other) {
        case (.string, _): self
        case (.keyValueList(let lhs), .keyValueList(let rhs)): .keyValueList(lhs.merged(with: rhs))
        case (.keyValueList, _): self
        }
    }
}

public typealias TracePropagationPreexistingHeaderKeys = Set<String>
