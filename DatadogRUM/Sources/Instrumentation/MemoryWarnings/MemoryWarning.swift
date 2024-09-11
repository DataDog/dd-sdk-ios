/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import UIKit

/// Represents a memory warning
internal struct MemoryWarning {
    /// The date when the memory warning was received.
    let date: Date

    /// The backtrace at the moment of memory warning.
    let backtrace: BacktraceReport?

    /// Creates a new instance of `MemoryWarning
    /// - Parameters:
    ///   - date: Date when the memory warning was received.
    ///   - backtrace: Backtrace at the moment of memory warning.
    init(
        date: Date,
        backtrace: BacktraceReport?
    ) {
        self.date = date
        self.backtrace = backtrace
    }
}
