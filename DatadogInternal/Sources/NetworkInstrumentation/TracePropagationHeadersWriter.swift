/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Write interface for a custom carrier
public protocol TracePropagationHeadersWriter {
    var traceHeaderFields: [String: String] { get }

    var traceHeaders: [String: TracePropagationHeaderValue] { get }

    func write(traceContext: TraceContext)
}

extension TracePropagationHeadersWriter {
    public var traceHeaderFields: [String: String] {
        traceHeaders.mapValues { $0.description }
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
}

public typealias TracePropagationPreexistingHeaderKeys = Set<String>
