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
internal enum Trilean: Int, Encodable, Hashable, Sendable {
    case notSet = 0
    case `true` = 1
    case `false` = 2
}
