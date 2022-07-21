/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Builds `URLRequest` for sending data to Datadog.
/* public */ internal struct URLRequestBuilder {
    enum QueryItem {
        /// `ddsource={source}` query item
        case ddsource(source: String)
        /// `ddtags={tag1},{tag2},...` query item
        case ddtags(tags: [String])
    }

    struct HTTPHeader {
        static let contentTypeHeaderField = "Content-Type"
        static let contentEncodingHeaderField = "Content-Encoding"
        static let userAgentHeaderField = "User-Agent"
        static let ddAPIKeyHeaderField = "DD-API-KEY"
        static let ddEVPOriginHeaderField = "DD-EVP-ORIGIN"
        static let ddEVPOriginVersionHeaderField = "DD-EVP-ORIGIN-VERSION"
        static let ddRequestIDHeaderField = "DD-REQUEST-ID"

        enum ContentType: String {
            case applicationJSON = "application/json"
            case textPlainUTF8 = "text/plain;charset=UTF-8"
        }

        let field: String
        let value: () -> String

        // MARK: - Standard Headers

        /// Standard "Content-Type" header.
        static func contentTypeHeader(contentType: ContentType) -> HTTPHeader {
            return HTTPHeader(field: contentTypeHeaderField, value: { contentType.rawValue })
        }

        /// Standard "User-Agent" header.
        static func userAgentHeader(appName: String, appVersion: String, device: DeviceInfo) -> HTTPHeader {
            var sanitizedAppName = appName

            if let regex = try? NSRegularExpression(pattern: "[^a-zA-Z0-9 -]+") {
                sanitizedAppName = regex.stringByReplacingMatches(
                    in: appName,
                    range: NSRange(appName.startIndex..<appName.endIndex, in: appName),
                    withTemplate: ""
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let agent = "\(sanitizedAppName)/\(appVersion) CFNetwork (\(device.name); \(device.osName)/\(device.osVersion))"
            return HTTPHeader(field: userAgentHeaderField, value: { agent })
        }

        // MARK: - Datadog Headers

        /// Datadog request authentication header.
        static func ddAPIKeyHeader(clientToken: String) -> HTTPHeader {
            return HTTPHeader(field: ddAPIKeyHeaderField, value: { clientToken })
        }

        /// An observability and troubleshooting Datadog header for tracking the origin which is sending the request.
        static func ddEVPOriginHeader(source: String) -> HTTPHeader {
            return HTTPHeader(field: ddEVPOriginHeaderField, value: { source })
        }

        /// An observability and troubleshooting Datadog header for tracking the origin which is sending the request.
        static func ddEVPOriginVersionHeader(sdkVersion: String) -> HTTPHeader {
            return HTTPHeader(field: ddEVPOriginVersionHeaderField, value: { sdkVersion })
        }

        /// An optional Datadog header for debugging Intake requests by their ID.
        static func ddRequestIDHeader() -> HTTPHeader {
            return HTTPHeader(field: ddRequestIDHeaderField, value: { UUID().uuidString })
        }
    }
    /// Upload `URL`.
    private let url: URL
    /// HTTP headers.
    private let headers: [HTTPHeader]

    // MARK: - Initialization

    init(
        url: URL,
        queryItems: [QueryItem],
        headers: [HTTPHeader]
    ) {
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)

        if !queryItems.isEmpty {
            urlComponents?.queryItems = queryItems.map { .init($0) }
        }

        self.url = urlComponents?.url ?? url
        self.headers = headers
    }

    /// Creates `URLRequest` for uploading given `data` to Datadog.
    /// - Parameter data: data to be uploaded
    /// - Returns: the `URLRequest` object and `DD-REQUEST-ID` header value (for debugging).
    func uploadRequest(with data: Data) -> URLRequest {
        var request = URLRequest(url: url)
        var headers: [String: String] = [:]
        self.headers.forEach { headers[$0.field] = $0.value() }
        request.httpMethod = "POST"

        if let body = Deflate.encode(data) {
            headers[HTTPHeader.contentEncodingHeaderField] = "deflate"
            request.httpBody = body
        } else {
            request.httpBody = data
            DD.telemetry.debug(
                """
                Failed to compress request payload
                - url: \(url)
                - uncompressed-size: \(data.count)
                """
            )
        }

        request.allHTTPHeaderFields = headers
        return request
    }
}

extension URLQueryItem {
    init(_ query: URLRequestBuilder.QueryItem) {
        switch query {
        case .ddsource(let source):
            self = URLQueryItem(name: "ddsource", value: source)
        case .ddtags(let tags):
            self = URLQueryItem(name: "ddtags", value: tags.joined(separator: ","))
        }
    }
}
