/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

// MARK: - Extracting SR context from `DatadogContext`

extension DatadogContext {
    /// The value indicating if replay is being performed by Session Replay.
    var hasReplay: Bool? {
        additionalContext(ofType: SessionReplayCoreContext.HasReplay.self)?.value
    }

    /// The value of `[String: Int64]` that indicates number of records recorded for a given viewID.
    var recordsCountByViewID: [String: Int64] {
        additionalContext(ofType: SessionReplayCoreContext.RecordsCount.self)?.value ?? [:]
    }
}
