/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Ensures the provided block is executed on the main thread, synchronously, rethrowing any error.
/// - Parameter block: A closure that may throw an error.
/// - Returns: The value produced by the closure.
/// - Throws: Whatever the closure itself might throw.
public func runOnMainThreadSync<T>(_ block: () throws -> T) rethrows -> T {
    if Thread.isMainThread {
        return try block()
    } else {
        return try DispatchQueue.main.sync(execute: block)
    }
}
