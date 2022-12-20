/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Retries given `block` several `times` in predefined `delay` until it does not throw an error.
/// If all tries resulted with error, the last `Error` is thrown from this function.
internal func retry<R>(times: UInt, delay: TimeInterval, block: () throws -> R) throws -> R {
    for _ in (1..<times) {
        do {
            return try block()
        } catch {
            Thread.sleep(forTimeInterval: delay)
        }
    }

    return try block()
}
