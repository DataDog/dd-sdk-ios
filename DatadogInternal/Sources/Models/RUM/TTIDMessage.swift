/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Message payload used to signal the TTID (Time to initial display).
public struct TTIDMessage {
    /// Correlation context that contains identifiers that will enable data correlation
    /// across different telemetry streams.
    public let context: [String: Encodable]
    /// Vital info associated with the TTID.
    public let vital: Vital

    /// Creates a new message payload.
    ///
    /// - Parameters
    ///   - context: Correlation context containing IDs for data correlation.
    ///   - vital: Vital info for data correlation.
    public init(context: [String: Encodable], vital: Vital) {
        self.context = context
        self.vital = vital
    }
}
