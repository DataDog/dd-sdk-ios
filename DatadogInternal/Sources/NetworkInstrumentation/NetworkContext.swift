/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Describes current Datadog SDK context, so the app state information can be attached to
/// instrumented Network traces.
public struct NetworkContext {
    public struct RUMContext: Decodable {
        enum CodingKeys: String, CodingKey {
            case sessionID = "session.id"
        }
        public let sessionID: String
    }

    /// Provides the current active RUM context, if any
    public var rumContext: RUMContext?
}
