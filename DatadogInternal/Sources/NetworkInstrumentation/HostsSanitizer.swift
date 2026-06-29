/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public protocol HostsSanitizing {
    func sanitized(hosts: Set<String>, warningMessage: String) -> Set<String>
    func sanitized(
        hostsWithTracingHeaderTypes: [String: Set<TracingHeaderType>],
        warningMessage: String
    ) -> [String: Set<TracingHeaderType>]
}

public struct HostsSanitizer: HostsSanitizing {
    private let hostRegex = #"^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$"#
    private let ipRegex = #"^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$"#
    private let wildcardAllowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-*")

    public init() { }

    private func sanitize(host: String, warningMessage: String) -> (String?, String?) {
        if host.contains("*") {
            return sanitizeWildcardPattern(host)
        } else if let sanitizedHost = URL(string: host)?.host {
            // if an URL is given instead of the host, take its `host` part
            let warning = "'\(host)' is an url and will be sanitized to: '\(sanitizedHost)'."
            return (sanitizedHost, warning)
        } else if host.range(of: ipRegex, options: .regularExpression) != nil {
            // if a valid IP address is given, accept it
            return (host, nil)
        } else if host.range(of: hostRegex, options: .regularExpression) != nil {
            // if a valid host name is given, accept it
            return (host, nil)
        } else {
            // otherwise, drop
            let warning = "'\(host)' is not a valid host name and will be dropped."
            return (nil, warning)
        }
    }

    private func sanitizeWildcardPattern(_ pattern: String) -> (String?, String?) {
        let lowercased = pattern.lowercased()
        guard lowercased.unicodeScalars.allSatisfy({ wildcardAllowedCharacters.contains($0) }) else {
            return (nil, "'\(pattern)' is not a valid host pattern and will be dropped.")
        }
        guard lowercased.filter({ $0 == "*" }).count == 1 else {
            return (nil, "'\(pattern)' is not a valid host pattern and will be dropped.")
        }
        guard lowercased.contains(".") else {
            return (nil, "'\(pattern)' is not a valid host pattern and will be dropped.")
        }
        let parts = lowercased.split(separator: "*", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts[1].hasPrefix("."), parts[1].count > 1 else {
            return (nil, "'\(pattern)' is not a valid host pattern and will be dropped.")
        }
        return (lowercased, nil)
    }

    private func printWarnings(_ warningMessage: String, _ warnings: [String]) {
        warnings.forEach { warning in
            consolePrint(
                    """
                    ⚠️ \(warningMessage): \(warning)
                    """,
                    .warn
            )
        }
    }

    public func sanitized(hosts: Set<String>, warningMessage: String) -> Set<String> {
        var warnings: [String] = []

        let array: [String] = hosts.compactMap { host in
            let (sanitizedHost, warning) = sanitize(host: host, warningMessage: warningMessage)
            if let warning = warning {
                warnings.append(warning)
            }
            return sanitizedHost
        }

        printWarnings(warningMessage, warnings)

        return Set(array)
    }

    public func sanitized(
        hostsWithTracingHeaderTypes: [String: Set<TracingHeaderType>],
        warningMessage: String
    ) -> [String: Set<TracingHeaderType>] {
        var warnings: [String] = []

        let sanitized: [String: Set<TracingHeaderType>] = hostsWithTracingHeaderTypes.reduce(into: [:]) { partialResult, item in
            let host = item.key
            let (sanitizedHost, warning) = sanitize(host: host, warningMessage: warningMessage)
            if let warning = warning {
                warnings.append(warning)
            }
            if let sanitizedHost = sanitizedHost {
                partialResult[sanitizedHost] = item.value
            }
        }

        printWarnings(warningMessage, warnings)

        return sanitized
    }
}
