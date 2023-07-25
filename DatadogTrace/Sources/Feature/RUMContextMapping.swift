/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// RUM context in `DatadogContext.featureAttributes` uses different keys than the ones we need to set
/// in log event for Log <> RUM link. This function does necessary re-mapping to isolate this logic temporarily until
/// we discuss standard solution.
internal func mapRUMContextAttributeKeyToSpanTagName(_ originalKey: String) -> String {
    switch originalKey {
    case "application.id":
        return "_dd.application.id"
    case "session.id":
        return "_dd.session.id"
    case "view.id":
        return "_dd.view.id"
    case "user_action.id":
        return "_dd.action.id"
    default:
        return originalKey
    }
}
