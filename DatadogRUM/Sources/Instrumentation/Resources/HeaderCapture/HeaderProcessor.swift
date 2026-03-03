/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Processes HTTP headers from intercepted URLSession requests, applying security filtering,
/// size limits, and header resolution based on the configured `TrackResourceHeaders`.
internal struct HeaderProcessor {
    /// Maximum byte size for a single header value.
    static let maxValueSize = 128
    /// Maximum number of headers per direction (request/response).
    static let maxHeaderCount = 100
    /// Maximum total byte size for all collected headers combined (both key and value).
    static let maxTotalSize = 2_048

    /// Default request headers to capture.
    private static let defaultRequestHeaders: Set<String> = [
        "cache-control",
        "content-type"
    ]

    /// Default response headers to capture.
    private static let defaultResponseHeaders: Set<String> = [
        "cache-control",
        "content-encoding",
        "content-length",
        "content-type",
        "etag",
        "age",
        "expires",
        "vary",
        "server-timing",
        "x-cache"
    ]

    /// iOS-managed headers that are always omitted from request capture.
    /// These are set by the URL Loading System and should not be reported as user-provided request headers.
    /// Ref: https://developer.apple.com/documentation/foundation/nsurlrequest#Reserved-HTTP-headers
    private static let reservedRequestHeaders: Set<String> = [
        "content-length",
        "authorization",
        "connection",
        "host",
        "proxy-authenticate",
        "proxy-authorization",
        "www-authenticate"
    ]

    /// Regex pattern to catch sensitive headers (auth, cookies, tokens, secrets, IPs, etc.).
    // swiftlint:disable:next force_try
    private static let securityPattern: NSRegularExpression = try! NSRegularExpression(
        pattern: "(token|cookie|secret|authorization|password|credential|bearer|(api|secret|access|app).?key|forwarded|real.?ip|connecting.?ip|client.?ip)",
        options: .caseInsensitive
    )

    private let config: RUM.Configuration.URLSessionTracking.TrackResourceHeaders

    init(config: RUM.Configuration.URLSessionTracking.TrackResourceHeaders) {
        self.config = config
    }

    /// Processes request and response headers based on the configured rules.
    ///
    /// - Parameters:
    ///   - requestHeaders: The request headers from `URLRequest.allHTTPHeaderFields`.
    ///   - responseHeaders: The response headers from `HTTPURLResponse.allHeaderFields`.
    /// - Returns: A tuple of filtered request and response header dictionaries.
    func process(
        requestHeaders: [String: String]?,
        responseHeaders: [AnyHashable: Any]?
    ) -> (request: [String: String], response: [String: String]) {
        switch config {
        case .disabled:
            return (request: [:], response: [:])
        case .defaults, .custom:
            let (captureRequest, captureResponse) = buildCaptureList()
            let request = filterRequestHeaders(requestHeaders, capturedHeaders: captureRequest)
            let response = filterResponseHeaders(responseHeaders, capturedHeaders: captureResponse)
            return (request: request, response: response)
        }
    }

    // MARK: - Private

    /// Resolves the ordered list of header names to capture for request and response based on the configuration rules.
    /// Default headers are always placed first to ensure they get budget priority over custom headers.
    private func buildCaptureList() -> (request: [String], response: [String]) {
        let rules: [RUM.Configuration.URLSessionTracking.HeaderCaptureRule]

        switch config {
        case .disabled:
            return (request: [], response: [])
        case .defaults:
            rules = [.defaults]
        case .custom(let customRules):
            rules = customRules
        }

        var requestHeaders: [String] = []
        var responseHeaders: [String] = []
        var seenRequests = Set<String>()
        var seenResponses = Set<String>()

        for rule in rules {
            switch rule {
            case .defaults:
                for name in Self.defaultRequestHeaders where seenRequests.insert(name).inserted {
                    requestHeaders.append(name)
                }
                for name in Self.defaultResponseHeaders where seenResponses.insert(name).inserted {
                    responseHeaders.append(name)
                }
            case .matchHeaders(let names):
                for name in names {
                    let lowercased = name.lowercased()
                    if seenRequests.insert(lowercased).inserted {
                        requestHeaders.append(lowercased)
                    }
                    if seenResponses.insert(lowercased).inserted {
                        responseHeaders.append(lowercased)
                    }
                }
            }
        }

        return (request: requestHeaders, response: responseHeaders)
    }

    /// Filters request headers.
    private func filterRequestHeaders(_ headers: [String: String]?, capturedHeaders: [String]) -> [String: String] {
        guard let headers else {
            return [:]
        }
        // Build a case-insensitive lookup from the raw headers
        let normalized = Dictionary(headers.map { ($0.key.lowercased(), ($0.key, $0.value)) }, uniquingKeysWith: { _, last in last })
        return filterHeaders(normalized, capturedHeaders: capturedHeaders, excluded: Self.reservedRequestHeaders)
    }

    /// Filters response headers.
    private func filterResponseHeaders(_ headers: [AnyHashable: Any]?, capturedHeaders: [String]) -> [String: String] {
        guard let headers else {
            return [:]
        }
        // Build a case-insensitive lookup, keeping only String key/value pairs
        var normalized: [String: (String, String)] = [:]
        for (rawKey, rawValue) in headers {
            guard let key = rawKey as? String, let value = rawValue as? String else { continue }
            normalized[key.lowercased()] = (key, value)
        }
        return filterHeaders(normalized, capturedHeaders: capturedHeaders)
    }

    /// Shared filtering logic: iterates over the ordered capture list to ensure default headers
    /// get budget priority over custom ones. Applies security pattern, excluded set, and size limits.
    private func filterHeaders(
        _ headersByLowercasedName: [String: (originalKey: String, value: String)],
        capturedHeaders: [String],
        excluded: Set<String> = []
    ) -> [String: String] {
        guard !headersByLowercasedName.isEmpty else {
            return [:]
        }

        var result: [String: String] = [:]
        var totalSize = 0

        for name in capturedHeaders {
            // Look up the header in the input (name is already lowercased)
            guard let (originalKey, value) = headersByLowercasedName[name] else { continue }
            // Skip iOS reserved headers
            guard !excluded.contains(name) else { continue }
            // Skip sensitive headers (auth, cookies, tokens, etc.)
            guard !matchesSecurityPattern(name) else { continue }
            // Enforce max header count
            guard result.count < Self.maxHeaderCount else { break }

            let truncatedValue = truncateValue(value)
            let entrySize = originalKey.utf8.count + truncatedValue.utf8.count

            // Enforce total size budget
            guard totalSize + entrySize <= Self.maxTotalSize else { break }

            result[originalKey] = truncatedValue
            totalSize += entrySize
        }

        return result
    }

    /// Truncates a header value to `maxValueSize` bytes, ensuring valid UTF-8.
    private func truncateValue(_ value: String) -> String {
        guard value.utf8.count > Self.maxValueSize else {
            return value
        }

        // Truncate at UTF-8 byte boundary
        let utf8 = value.utf8
        let truncatedUTF8 = utf8.prefix(Self.maxValueSize)

        // Ensure we don't cut in the middle of a multi-byte character
        return String(truncatedUTF8) ?? String(value.prefix(Self.maxValueSize))
    }

    /// Checks whether the header name matches the security regex pattern.
    private func matchesSecurityPattern(_ lowercasedName: String) -> Bool {
        let range = NSRange(lowercasedName.startIndex..., in: lowercasedName)
        return Self.securityPattern.firstMatch(in: lowercasedName, range: range) != nil
    }
}
