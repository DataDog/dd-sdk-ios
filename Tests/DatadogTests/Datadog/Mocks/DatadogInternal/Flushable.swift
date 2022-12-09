/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

@testable import Datadog

/// `Flushable` object resets its state on flush.
///
/// Calling `flush` method should reset any in-memory and persistent
/// data to initialised state.
internal protocol Flushable {
    /// Flush data and reset state.
    func flush()
}

extension LoggingFeature: Flushable {
    func flush() {
        deinitialize()
    }
}

extension TracingFeature: Flushable {
    func flush() {
        deinitialize()
    }
}

extension RUMFeature: Flushable {
    func flush() {
        deinitialize()
    }
}

extension RUMInstrumentation: Flushable {
    func flush() {
        deinitialize()
    }
}

extension URLSessionAutoInstrumentation: Flushable {
    func flush() {
        deinitialize()
    }
}
