/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// HTTP headers associated with requests send by SDK.
internal struct HTTPHeaders {
    enum ContentType: String {
        case applicationJSON = "application/json"
        case textPlainUTF8 = "text/plain;charset=UTF-8"
    }

    struct HTTPHeader {
        let field: String
        let value: String

        // MARK: - Supported headers

        static func contentTypeHeader(contentType: ContentType) -> HTTPHeader {
            return HTTPHeader(field: "Content-Type", value: contentType.rawValue)
        }

        static func userAgentHeader(appName: String, appVersion: String, device: MobileDevice) -> HTTPHeader {
            return HTTPHeader(
                field: "User-Agent",
                value: "\(appName)/\(appVersion) CFNetwork (\(device.model); \(device.osName)/\(device.osVersion))"
            )
        }

        // MARK: - Initialization

        private init(field: String, value: String) {
            self.field = field
            self.value = value
        }
    }

    let all: [String: String]

    init(headers: [HTTPHeader]) {
        self.all = headers.reduce([:]) { acc, next in
            var dictionary = acc
            dictionary[next.field] = next.value
            return dictionary
        }
    }
}
