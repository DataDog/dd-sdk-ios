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
            let request = filterRequestHeaders(requestHeaders, capturing: captureRequest)
            let response = filterResponseHeaders(responseHeaders, capturing: captureResponse)
            return (request: request, response: response)
        }
    }

    // MARK: - Private

    /// Resolves the set of header names to capture for request and response based on the configuration rules.
    private func buildCaptureList() -> (request: Set<String>, response: Set<String>) {
        var requestHeaders = Set<String>()
        var responseHeaders = Set<String>()

        let rules: [RUM.Configuration.URLSessionTracking.HeaderCaptureRule]

        switch config {
        case .disabled:
            return (request: [], response: [])
        case .defaults:
            rules = [.defaults]
        case .custom(let customRules):
            rules = customRules
        }

        for rule in rules {
            switch rule {
            case .defaults:
                requestHeaders.formUnion(Self.defaultRequestHeaders)
                responseHeaders.formUnion(Self.defaultResponseHeaders)
            case .matchHeaders(let names):
                let lowercased = Set(names.map { $0.lowercased() })
                requestHeaders.formUnion(lowercased)
                responseHeaders.formUnion(lowercased)
            }
        }

        return (request: requestHeaders, response: responseHeaders)
    }

    /// Filters request headers.
    private func filterRequestHeaders(_ headers: [String: String]?, capturing: Set<String>) -> [String: String] {
        guard let headers else {
            return [:]
        }
        return filterHeaders(headers.map { ($0.key, $0.value) }, capturing: capturing, excluded: Self.reservedRequestHeaders)
    }

    /// Filters response headers.
    private func filterResponseHeaders(_ headers: [AnyHashable: Any]?, capturing: Set<String>) -> [String: String] {
        guard let headers else {
            return [:]
        }
        let stringPairs = headers.compactMap { rawKey, rawValue -> (String, String)? in
            guard let key = rawKey as? String, let value = rawValue as? String else {
                return nil
            }
            return (key, value)
        }
        return filterHeaders(stringPairs, capturing: capturing)
    }

    /// Shared filtering logic: applies capture list, security pattern, excluded set, and size limits.
    private func filterHeaders(_ headers: [(String, String)], capturing: Set<String>, excluded: Set<String> = []) -> [String: String] {
        guard !headers.isEmpty else {
            return [:]
        }

        var result: [String: String] = [:]
        var totalSize = 0

        for (key, value) in headers {
            let lowercasedKey = key.lowercased()

            // Only capture headers in the configured list
            guard capturing.contains(lowercasedKey) else { continue }
            // Skip iOS reserved headers
            guard !excluded.contains(lowercasedKey) else { continue }
            // Skip sensitive headers (auth, cookies, tokens, etc.)
            guard !matchesSecurityPattern(lowercasedKey) else { continue }
            // Enforce max header count
            guard result.count < Self.maxHeaderCount else { break }

            let truncatedValue = truncateValue(value)
            let entrySize = key.utf8.count + truncatedValue.utf8.count

            // Enforce total size budget
            guard totalSize + entrySize <= Self.maxTotalSize else { break }

            result[key] = truncatedValue
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
