/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Builds `URLRequest` for sending data to Datadog.
public struct URLRequestBuilder {
    public enum QueryItem {
        /// `ddsource={source}` query item
        case ddsource(source: String)
        /// `ddtags={tag1},{tag2},...` query item
        case ddtags(tags: [String])
    }

    public struct HTTPHeader {
        public static let contentTypeHeaderField = "Content-Type"
        public static let contentEncodingHeaderField = "Content-Encoding"
        public static let userAgentHeaderField = "User-Agent"
        public static let ddAPIKeyHeaderField = "DD-API-KEY"
        public static let ddEVPOriginHeaderField = "DD-EVP-ORIGIN"
        public static let ddEVPOriginVersionHeaderField = "DD-EVP-ORIGIN-VERSION"
        public static let ddRequestIDHeaderField = "DD-REQUEST-ID"

        public enum ContentType {
            case applicationJSON
            case textPlainUTF8
            case multipartFormData(boundary: String)

            public var toString: String {
                switch self {
                case .applicationJSON: return "application/json"
                case .textPlainUTF8: return "text/plain;charset=UTF-8"
                case .multipartFormData(let boundary): return "multipart/form-data; boundary=\(boundary)"
                }
            }
        }

        let field: String
        let value: () -> String

        public init(field: String, value: @escaping () -> String) {
            self.field = field
            self.value = value
        }

        // MARK: - Standard Headers

        /// Standard "Content-Type" header.
        public static func contentTypeHeader(contentType: ContentType) -> HTTPHeader {
            return HTTPHeader(field: contentTypeHeaderField, value: { contentType.toString })
        }

        /// Standard "User-Agent" header.
        public static func userAgentHeader(appName: String, appVersion: String, device: DeviceInfo) -> HTTPHeader {
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
        public static func ddAPIKeyHeader(clientToken: String) -> HTTPHeader {
            return HTTPHeader(field: ddAPIKeyHeaderField, value: { clientToken })
        }

        /// An observability and troubleshooting Datadog header for tracking the origin which is sending the request.
        public static func ddEVPOriginHeader(source: String) -> HTTPHeader {
            return HTTPHeader(field: ddEVPOriginHeaderField, value: { source })
        }

        /// An observability and troubleshooting Datadog header for tracking the origin which is sending the request.
        public static func ddEVPOriginVersionHeader(sdkVersion: String) -> HTTPHeader {
            return HTTPHeader(field: ddEVPOriginVersionHeaderField, value: { sdkVersion })
        }

        /// An optional Datadog header for debugging Intake requests by their ID.
        public static func ddRequestIDHeader() -> HTTPHeader {
            return HTTPHeader(field: ddRequestIDHeaderField, value: { UUID().uuidString })
        }
    }
    /// Upload `URL`.
    private let url: URL
    /// HTTP headers.
    private let headers: [HTTPHeader]
    /// Telemetry interface.
    private let telemetry: Telemetry

    // MARK: - Initialization

    public init(
        url: URL,
        queryItems: [QueryItem],
        headers: [HTTPHeader],
        telemetry: Telemetry = NOPTelemetry()
    ) {
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)

        if !queryItems.isEmpty {
            urlComponents?.queryItems = queryItems.map { .init($0) }
        }

        self.url = urlComponents?.url ?? url
        self.headers = headers
        self.telemetry = telemetry
    }

    /// Creates `URLRequest` for uploading given `body` to Datadog.
    ///
    /// - Parameter body: HTTP body to be attached to request
    /// - Parameter compress: if `body` should be compressed into ZLIB Compressed Data Format (IETF RFC 1950)
    /// - Returns: the `URLRequest` object.
    public func uploadRequest(with body: Data, compress: Bool = true) -> URLRequest {
        var request = URLRequest(url: url)
        var headers: [String: String] = [:]
        self.headers.forEach { headers[$0.field] = $0.value() }
        request.httpMethod = "POST"

        if compress, let deflatedBody = Deflate.encode(body) {
            headers[HTTPHeader.contentEncodingHeaderField] = "deflate"
            request.httpBody = deflatedBody
        } else {
            request.httpBody = body
            if compress {
                telemetry.debug(
                    """
                    Failed to compress request payload
                    - url: \(url)
                    - uncompressed-size: \(body.count)
                    """
                )
            }
        }

        headers.forEach { field, value in
            request.setValue(value, forHTTPHeaderField: field)
        }
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
