/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

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
        "x-cache",
        "cf-cache-status",
        "x-vercel-cache"
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
    /// Ordered request header names to capture, without reserved and sensitive headers.
    private let requestCaptureList: [String]
    /// Ordered response header names to capture, without sensitive headers.
    private let responseCaptureList: [String]

    init(config: RUM.Configuration.URLSessionTracking.TrackResourceHeaders) {
        self.config = config
        let (request, response) = Self.buildCaptureList(for: config)
        self.requestCaptureList = request.filter { !Self.reservedRequestHeaders.contains($0) && !Self.matchesSecurityPattern($0) }
        self.responseCaptureList = response.filter { !Self.matchesSecurityPattern($0) }
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
            let request = filterRequestHeaders(requestHeaders, capturedHeaders: requestCaptureList)
            let response = filterResponseHeaders(responseHeaders, capturedHeaders: responseCaptureList)
            return (request: request, response: response)
        }
    }

    // MARK: - Private

    /// Resolves the ordered list of header names to capture for request and response based on the configuration rules.
    /// Default headers are always placed first to ensure they get budget priority over custom headers.
    private static func buildCaptureList(
        for config: RUM.Configuration.URLSessionTracking.TrackResourceHeaders
    ) -> (request: [String], response: [String]) {
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
        // Build a case-insensitive lookup from the raw headers (values only, keys will be lowercased in output)
        let normalized = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
        return filterHeaders(normalized, capturedHeaders: capturedHeaders)
    }

    /// Filters response headers.
    private func filterResponseHeaders(_ headers: [AnyHashable: Any]?, capturedHeaders: [String]) -> [String: String] {
        guard let headers else {
            return [:]
        }
        // Build a case-insensitive lookup (keys will be lowercased in output).
        var normalized: [String: String] = [:]
        for (rawKey, rawValue) in headers {
            guard let key = rawKey as? String else { continue }
            let value = (rawValue as? String) ?? String(describing: rawValue)
            normalized[key.lowercased()] = value
        }
        return filterHeaders(normalized, capturedHeaders: capturedHeaders)
    }

    /// Shared filtering logic: iterates over the ordered capture list to ensure default headers
    /// get budget priority over custom ones. Applies size limits; reserved and sensitive headers are
    /// already removed from the capture lists. A header that would exceed the total size budget is skipped,
    /// and later headers that still fit are captured.
    /// All output keys are lowercased for cross-platform consistency.
    private func filterHeaders(
        _ valuesByLowercasedName: [String: String],
        capturedHeaders: [String]
    ) -> [String: String] {
        guard !valuesByLowercasedName.isEmpty else {
            return [:]
        }

        var result: [String: String] = [:]
        var totalSize = 0
        var skippedHeaders: [String] = []

        for name in capturedHeaders {
            // Look up the header value in the input (name is already lowercased)
            guard let value = valuesByLowercasedName[name] else { continue }
            // Enforce max header count
            guard result.count < Self.maxHeaderCount else { break }

            let truncatedValue = truncateValue(value)
            let entrySize = name.utf8.count + truncatedValue.utf8.count

            // Enforce total size budget, skipping headers that don't fit
            guard totalSize + entrySize <= Self.maxTotalSize else {
                skippedHeaders.append(name)
                continue
            }

            result[name] = truncatedValue
            totalSize += entrySize
        }

        if !skippedHeaders.isEmpty {
            let names = skippedHeaders.map { "'\($0)'" }.joined(separator: ", ")
            DD.logger.debug("Skipping headers \(names): adding them would exceed the \(Self.maxTotalSize) byte limit.")
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
    private static func matchesSecurityPattern(_ lowercasedName: String) -> Bool {
        let range = NSRange(lowercasedName.startIndex..., in: lowercasedName)
        return Self.securityPattern.firstMatch(in: lowercasedName, range: range) != nil
    }
}
