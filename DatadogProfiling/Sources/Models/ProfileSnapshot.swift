/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Captured profile data and its RUM context, ready to be written independently of the profiler.
internal struct ProfileSnapshot: @unchecked Sendable {
    let start: Date
    let end: Date
    let attachment: PprofAttachment
    let rumEvents: [RUMEvent]
    let attributes: [AttributeKey: AttributeValue]
    /// Captured with the profile, or resolved by the first session decision for a pending launch.
    var rumContext: RUMCoreContext? = nil
}
