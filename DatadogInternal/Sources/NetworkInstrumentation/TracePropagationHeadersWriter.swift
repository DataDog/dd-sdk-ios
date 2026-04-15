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
        traceHeaders.allHeadersInStringFormat
    }
}

fileprivate struct HeaderKey: Hashable, Comparable {
    let lowercased: String
    let original: String

    init(_ original: String) {
        self.original = original
        self.lowercased = original.lowercased() // Intentionally non localized, it uses Unicode definition of lowercasing.
    }

    static func == (lhs: HeaderKey, rhs: HeaderKey) -> Bool {
        lhs.lowercased == rhs.lowercased
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(lowercased)
    }

    static func < (lhs: HeaderKey, rhs: HeaderKey) -> Bool {
        lhs.lowercased < rhs.lowercased
    }
}






public struct TraceHeaders: ExpressibleByDictionaryLiteral {
    public struct Configuration {
        // TODO: RUM-13769 Find a decent name for this variable
        fileprivate let headersAllowedToPreExist: [HeaderKey: TracePropagationHeaderValue.KeyValuePairs.Configuration]

        public static let `default` = Configuration(headersAllowedToPreExist: [
            HeaderKey(W3CHTTPHeaders.baggage): .commaSeparatedPairs
        ])
    }

    public typealias Key = String

    public typealias Value = TracePropagationHeaderValue

    public static func merged(_ elements: [TraceHeaders]) -> TraceHeaders {
        elements.reduce([:]) { partialResult, element in
            partialResult.merged(with: element)
        }
    }

    private var storage: [HeaderKey: TracePropagationHeaderValue]

    public let configuration: Configuration

    private init(storage: [HeaderKey: TracePropagationHeaderValue], configuration: Configuration = .default) {
        self.storage = storage
        self.configuration = configuration
    }

    public init(dictionaryLiteral elements: (String, TracePropagationHeaderValue)...) {
        let elementsWithHeaderKeys = elements.map { (key, value) in (HeaderKey(key), value) }
        self.storage = Dictionary(elementsWithHeaderKeys, uniquingKeysWith: { lhs, rhs in rhs })
        self.configuration = .default
    }

    init(headers: [String: TracePropagationHeaderValue], configuration: Configuration = .default) {
        let elementsWithHeaderKeys = headers
            .map { (key, value) in (HeaderKey(key), value) }
        self.storage = Dictionary(elementsWithHeaderKeys, uniquingKeysWith: { lhs, rhs in rhs })
        self.configuration = configuration
    }

    func merged(with other: TraceHeaders) -> TraceHeaders {
        .init(
            storage: storage.merging(other.storage) { lhs, rhs in
                lhs.merged(with: rhs)
            }
        )
    }

    public func filtered(by request: URLRequest) -> TraceHeaders {
        return TraceHeaders(
            storage: storage.filter { key, _ in
                // Keep key is the header may pre-exist, or if it does not exist yet.
                configuration.headersAllowedToPreExist[key] != nil ||
                request.value(forHTTPHeaderField: key.original) == nil
            }
        )
    }

    public var isEmpty: Bool {
        storage.isEmpty
    }

    public subscript(key: String) -> TracePropagationHeaderValue? {
        get { return storage[HeaderKey(key)] }
        set { storage[HeaderKey(key)] = newValue }
    }

    public subscript(stringValue key: String) -> String? {
        get { return storage[HeaderKey(key)]?.description }
    }

    public func write(to request: inout URLRequest) {
        storage.forEach { (key, value) in
            let previousValue = request.value(forHTTPHeaderField: key.original)

            guard let previousValue else {
                // Normal case, value did not exist in the request, we set it, we're done.
                request.setValue(value.description, forHTTPHeaderField: key.original)
                return
            }

            // Value already exists. If it's part of the allowed to pre-exist list and its format
            // is a key-value list with the expected configuration, we merge it. Otherwise we don't
            // touch it.
            if let keyValuePairConfiguration = configuration.headersAllowedToPreExist[key],
               case let .keyValueList(keyValues) = value {
                if let previousKeyValues = TracePropagationHeaderValue.KeyValuePairs(fromHeaderValue: previousValue, configuration: keyValuePairConfiguration) {
                    let finalKeyValues = previousKeyValues.merged(with: keyValues)
                    request.setValue(finalKeyValues.description, forHTTPHeaderField: key.original)
                }
            }
        }
    }

    var allHeadersInStringFormat: [String: String] {
        let pairs = storage
            .map { key, value in
                (key.original, value.description)
            }

        return Dictionary(pairs) { lhs, rhs in
            rhs // This theoretically cannot happen, but we fail gracefully if it does.
        }
    }
}

public enum TracePropagationHeaderValue: CustomStringConvertible {
    public struct KeyValuePairs: CustomStringConvertible {
        public struct Configuration {
            let prefix: String?
            let keyValueSeparator: Character
            let pairSeparator: Character

            static let commaSeparatedPairs = Configuration(prefix: nil, keyValueSeparator: "=", pairSeparator: ",")
            static let tracestate = Configuration(prefix: "\(W3CHTTPHeaders.Constants.dd)=", keyValueSeparator: ":", pairSeparator: ";")
        }

        let values: [String: String]
        let configuration: Configuration

        init(values: [String: String], configuration: Configuration) {
            self.values = values
            self.configuration = configuration
        }

        init?(fromHeaderValue headerValue: String, configuration: Configuration) {
            let trimmedPrefixedValue = Substring(headerValue.trimmingCharacters(in: .whitespaces))
            guard trimmedPrefixedValue.isEmpty == false else {
                return nil
            }
            let trimmedValue: Substring
            if let prefix = configuration.prefix {
                guard trimmedPrefixedValue.starts(with: prefix) else {
                    return nil
                }
                trimmedValue = trimmedPrefixedValue[(trimmedPrefixedValue.index(trimmedPrefixedValue.startIndex, offsetBy: prefix.count))..<trimmedPrefixedValue.endIndex]
            } else {
                trimmedValue = trimmedPrefixedValue
            }
            let pairs = trimmedValue.split(separator: configuration.pairSeparator)
            let parsedPairs: [(String, String)] = pairs.compactMap {
                let elements = $0.split(separator: configuration.keyValueSeparator, maxSplits: 1)
                guard elements.count == 2 else {
                    return nil
                }
                return (
                    String(elements[0].trimmingCharacters(in: .whitespaces)),
                    String(elements[1].trimmingCharacters(in: .whitespaces))
                )
            }

            self.values = Dictionary(parsedPairs, uniquingKeysWith: { lhs, rhs in
                lhs
            })
            self.configuration = configuration
        }

        public var description: String {
            (configuration.prefix ?? "") + values
                .sorted { lhs, rhs in lhs.key < rhs.key }
                .map { pair in "\(pair.key)\(configuration.keyValueSeparator)\(pair.value)" }
                .joined(separator: String(configuration.pairSeparator))
        }

        func merged(with other: KeyValuePairs) -> KeyValuePairs {
            .init(
                values: values.merging(other.values, uniquingKeysWith: { lhs, rhs in rhs }),
                configuration: configuration
            )
        }
    }

    case string(String)
    // Ideally this should be an ordered dictionary, but for the sake of not
    // adding a 3rd party dependency, we do it manually.
    case keyValueList(KeyValuePairs)

    public var description: String {
        switch self {
        case .string(let string):
            string.description
        case .keyValueList(let keyValuePairs):
            keyValuePairs.description
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
