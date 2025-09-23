/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension FlagsClient {
    public struct Configuration {
        public let baseURL: String?
        public let customHeaders: [String: String]
        public let flaggingProxy: String?
        public let clientKey: String?

        public init(
            baseURL: String? = nil,
            customHeaders: [String: String] = [:],
            flaggingProxy: String? = nil,
            clientKey: String? = nil
        ) {
            self.baseURL = baseURL
            self.customHeaders = customHeaders
            self.flaggingProxy = flaggingProxy
            self.clientKey = clientKey
        }
    }
}
