/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Matches the protobuf `Trilean` enum used for `ClientGroupedStats.is_trace_root`.
///
/// Lives in `Stats/` because it is shared between the in-memory `StatsConcentrator`
/// aggregation pipeline and the wire-format `ClientGroupedStats` payload.
internal enum Trilean: Int, Hashable, Sendable {
    case notSet = 0
    case `true` = 1
    case `false` = 2
}

extension Trilean: Encodable {
    /// Encodes as `Int32` so the MsgPack wire format matches the protobuf-derived schema
    /// (which models `is_trace_root` as `int32`). The default raw-value synthesis would
    /// emit a platform-width `Int`, which routes through `Int64` on 64-bit platforms.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Int32(rawValue))
    }
}
