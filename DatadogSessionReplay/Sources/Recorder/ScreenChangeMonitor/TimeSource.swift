/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Minimal abstraction for retrieving current time values used by screen
// change monitoring internals.

#if os(iOS)
import Foundation

internal protocol TimeSource {
    var now: TimeInterval { get }
}
#endif
