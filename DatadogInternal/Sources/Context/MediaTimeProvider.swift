/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import QuartzCore

/// Provides current media uptime.
public protocol MediaTimeProvider: Sendable {
    /// Current media uptime.
    var now: CFTimeInterval { get }
}

public struct CurrentMediaTimeProvider: MediaTimeProvider {
    public init() { }
    /// Returns the current CoreAnimation absolute time.
    /// This is the result of calling mach_absolute_time() and converting the units to seconds.
    public var now: CFTimeInterval { CACurrentMediaTime() }
}
