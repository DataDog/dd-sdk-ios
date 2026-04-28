/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */
import Foundation

public struct TimeseriesConfig {
    public let applicationId: String
    public let sessionId: String
    public let sessionType: String
    public let source: String
    public let service: String?
    public let version: String?

    public init(applicationId: String, sessionId: String, sessionType: String, source: String, service: String?, version: String?) {
        self.applicationId = applicationId
        self.sessionId = sessionId
        self.sessionType = sessionType
        self.source = source
        self.service = service
        self.version = version
    }
}
