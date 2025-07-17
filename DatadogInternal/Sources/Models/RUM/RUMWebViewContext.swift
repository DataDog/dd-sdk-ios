/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public struct RUMWebViewContext: AdditionalContext {
    public static let key = "rum_webview"

    private var serverTimeOffsets: [String: TimeInterval]

    public init(serverTimeOffsets: [String: TimeInterval] = [:]) {
        self.serverTimeOffsets = serverTimeOffsets
    }

    public func serverTimeOffset(forView id: String) -> TimeInterval? {
        serverTimeOffsets[id]
    }

    public mutating func setServerTimeOffset(_ offset: TimeInterval, forView id: String) {
        serverTimeOffsets[id] = offset
    }
}
