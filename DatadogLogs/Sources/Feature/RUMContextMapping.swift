/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// RUM context in `DatadogContext.featureAttributes` uses different keys than the ones we need to set
/// in log event for Log <> RUM link. This function does necessary re-mapping to isolate this logic temporarily until
/// we discuss standard solution.
internal func mapRUMContextAttributeKeyToLogAttributeKey(_ originalKey: String) -> String {
    switch originalKey {
    case "application.id":
        return "application_id"
    case "session.id":
        return "session_id"
    default:
        return originalKey
    }
}
