/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// HTTP headers associated with requests send by SDK.
internal struct HTTPHeaders {
    private struct Constants {
        static let contentTypeField = "Content-Type"
        static let contentTypeValue = "application/json"
        static let userAgentField = "User-Agent"
    }

    let all: [String: String]

    init(appName: String, appVersion: String, device: MobileDevice) {
        self.all = [
            Constants.contentTypeField: Constants.contentTypeValue,
            Constants.userAgentField: "\(appName)/\(appVersion) CFNetwork (\(device.model); \(device.osName)/\(device.osVersion))"
        ]
    }
}
