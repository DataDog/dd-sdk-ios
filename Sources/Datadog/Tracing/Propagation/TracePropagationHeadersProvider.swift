/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Interface that defines shared responibilities of HTTP header writers.
public protocol TracePropagationHeadersProvider {
    var tracePropagationHTTPHeaders: [String: String] { get }
}
