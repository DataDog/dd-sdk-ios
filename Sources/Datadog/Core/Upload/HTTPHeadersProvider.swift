/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Provides HTTP headers associated with SDK requests.
internal struct HTTPHeadersProvider {
    enum ContentType: String {
        case applicationJSON = "application/json"
        case textPlainUTF8 = "text/plain;charset=UTF-8"
    }

    struct HTTPHeader {
        enum Value {
            /// If the header's value is constant.
            case constant(_ value: String)
            /// If the header's value is different each time.
            case dynamic(_ value: () -> String)
        }

        let field: String
        let value: Value

        // MARK: - Standard Headers

        static func contentTypeHeader(contentType: ContentType) -> HTTPHeader {
            return HTTPHeader(field: "Content-Type", value: .constant(contentType.rawValue))
        }

        static func userAgentHeader(appName: String, appVersion: String, device: MobileDevice) -> HTTPHeader {
            return HTTPHeader(
                field: "User-Agent",
                value: .constant("\(appName)/\(appVersion) CFNetwork (\(device.model); \(device.osName)/\(device.osVersion))")
            )
        }

        // MARK: - Datadog Headers

        /// Request authentication header.
        static func ddAPIKeyHeader(clientToken: String) -> HTTPHeader {
            return HTTPHeader(field: "DD-API-KEY", value: .constant(clientToken))
        }

        /// An observability and troubleshooting header for tracking the origin which is sending the request.
        static func ddEVPOriginHeader(source: String) -> HTTPHeader {
            return HTTPHeader(field: "DD-EVP-ORIGIN", value: .constant(source))
        }

        /// An observability and troubleshooting header for tracking the origin which is sending the request.
        static func ddEVPOriginVersionHeader() -> HTTPHeader {
            return HTTPHeader(field: "DD-EVP-ORIGIN-VERSION", value: .constant(sdkVersion))
        }

        /// An optional header for debugging Intake requests by their ID.
        static func ddRequestIDHeader() -> HTTPHeader {
            return HTTPHeader(field: "DD-REQUEST-ID", value: .dynamic({ UUID().uuidString }))
        }

        // MARK: - Initialization

        private init(field: String, value: Value) {
            self.field = field
            self.value = value
        }
    }

    /// Headers which value does not change.
    private var constantHeaders: [String: String] = [:]
    /// Headers which value does change over time.
    private var dynamicHeaders: [String: () -> String] = [:]

    /// Computes and returns headers to be associated with SDK request.
    var headers: [String: String] {
        var all = constantHeaders
        dynamicHeaders.forEach { field, value in all[field] = value() }
        return all
    }

    // MARK: - Initialization

    init(headers: [HTTPHeader]) {
        headers.forEach { header in
            switch header.value {
            case .constant(let value):
                constantHeaders[header.field] = value
            case .dynamic(let value):
                dynamicHeaders[header.field] = value
            }
        }
    }
}
