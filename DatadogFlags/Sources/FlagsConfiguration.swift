/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public struct FlagsClientConfiguration {
    public let clientToken: String
    public let environment: String
    public let baseURL: String?
    public let site: DatadogSite
    public let applicationId: String?
    public let customHeaders: [String: String]
    public let flaggingProxy: String?
    public init(
        clientToken: String,
        environment: String = "prod",
        baseURL: String? = nil,
        site: DatadogSite = .us1,
        applicationId: String? = nil,
        customHeaders: [String: String] = [:],
        flaggingProxy: String? = nil
    ) {
        self.clientToken = clientToken
        self.environment = environment
        self.baseURL = baseURL
        self.site = site
        self.applicationId = applicationId
        self.customHeaders = customHeaders
        self.flaggingProxy = flaggingProxy
    }
}
