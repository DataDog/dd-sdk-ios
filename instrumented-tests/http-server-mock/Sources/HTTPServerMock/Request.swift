/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Details of the request send to the Python server.
public struct Request {
    /// Original path of this request.
    public let path: String
    /// HTTP method of this request.
    public let httpMethod: String
    /// HTTP headers associated with this request.
    public let httpHeaders: [String]
    /// HTTP body of this request.
    public let httpBody: Data
}
