/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A struct that represents a dictionary of host names and tracing header types.
internal struct FirstPartyHosts: Equatable {
    fileprivate var hostsWithTracingHeaderTypes: [String: Set<TracingHeaderType>]

    var hosts: Set<String> {
        return Set(hostsWithTracingHeaderTypes.keys)
    }

    /// Creates a `FirstPartyHosts` instance with the given dictionary of host names and tracing header types.
    ///
    /// - Parameter hostsWithTracingHeaderTypes: The dictionary of host names and tracing header types.
    internal init(_ hostsWithTracingHeaderTypes: [String: Set<TracingHeaderType>] = [:]) {
        self.init(hostsWithTracingHeaderTypes: hostsWithTracingHeaderTypes)
    }

    internal init(
        hostsWithTracingHeaderTypes: [String: Set<TracingHeaderType>],
        hostsSanitizer: HostsSanitizing = HostsSanitizer()
    ) {
        self.hostsWithTracingHeaderTypes = hostsSanitizer.sanitized(
            hostsWithTracingHeaderTypes: hostsWithTracingHeaderTypes,
            warningMessage: "The first party host with header types configured for Datadog SDK is not valid"
        )
    }

    /// The function takes a `URL` and returns a `Set<TracingHeaderType>` of matching values.
    /// If one than more match is found it will return union of matching values.
    func tracingHeaderTypes(for url: URL?) -> Set<TracingHeaderType> {
        return hostsWithTracingHeaderTypes.compactMap { item -> Set<TracingHeaderType>? in
            let regex = "^(.*\\.)*\(NSRegularExpression.escapedPattern(for: item.key))$"
            if url?.host?.range(of: regex, options: .regularExpression) != nil {
                return item.value
            }
            return nil
        }
        .reduce(into: Set(), { partialResult, value in
            partialResult.formUnion(value)
        })
    }

    /// Returns `true` if given `URL` matches the first party hosts defined by the user; `false` otherwise.
    func isFirstParty(url: URL?) -> Bool {
        return !tracingHeaderTypes(for: url).isEmpty
    }

    // Returns `true` if given `String` can be parsed as a URL and matches the first
    // party hosts defined by the user; `false` otherwise
    func isFirstParty(string: String) -> Bool {
        guard let url = URL(string: string) else {
            return false
        }
        return isFirstParty(url: url)
    }
}

internal func += (left: inout FirstPartyHosts?, right: FirstPartyHosts) {
    left = FirstPartyHosts(
        left?.hostsWithTracingHeaderTypes.merging(right.hostsWithTracingHeaderTypes, uniquingKeysWith: { left, right in
            left.union(right)
        }) ?? right.hostsWithTracingHeaderTypes
    )
}
