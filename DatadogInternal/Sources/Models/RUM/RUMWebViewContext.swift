/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// RUM web-view specific context.
public struct RUMWebViewContext: AdditionalContext {
    /// The key used to identify this context in the core's additional context dictionary.
    public static let key = "rum_web_view"

    private var serverTimeOffsets: [String: TimeInterval]

    /// Creates a new WebView context.
    ///
    /// - Parameter serverTimeOffsets: Pre-existing server time offsets to initialize with.
    ///   Defaults to an empty dictionary for new contexts.
    public init(serverTimeOffsets: [String: TimeInterval] = [:]) {
        self.serverTimeOffsets = serverTimeOffsets
    }

    /// Retrieves the cached server time offset for a specific view event.
    public func serverTimeOffset(forView id: String) -> TimeInterval? {
        serverTimeOffsets[id]
    }

    /// Caches a server time offset for a specific view event.
    public mutating func setServerTimeOffset(_ offset: TimeInterval, forView id: String) {
        serverTimeOffsets[id] = offset
    }
}
