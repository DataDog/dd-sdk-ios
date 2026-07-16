/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import QuartzCore

/// Provides the current time used by recording components.
internal protocol TimeSource {
    var now: TimeInterval { get }
}

/// Time source backed by Core Animation's monotonic media time.
internal struct MediaTimeSource: TimeSource {
    var now: TimeInterval {
        CACurrentMediaTime()
    }
}
#endif
