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
public func runOnMainThreadSync<T>(_ block: @MainActor () throws -> T) rethrows -> T {
    if Thread.isMainThread {
        if #available(iOS 13.0, tvOS 13.0, *) {
            return try MainActor.assumeIsolated {
                return try block()
            }
        } else {
            // Does the same as MainActor.assumeIsolated on iOS 12.
            // This erases the @MainActor annotation from `block` and calls it synchronously.
            // Equivalent in intent to `MainActor.assumeIsolated { try block() }`,
            // but unlike `assumeIsolated`, this performs no runtime check that we are
            // actually on the MainActor, so it is only safe if the caller guarantees that.
            return try withoutActuallyEscaping(block) { block in
                let rawBlock = unsafeBitCast(block, to: (() throws -> T).self)
                return try rawBlock()
            }
        }
    } else {
        return try DispatchQueue.main.sync(execute: block)
    }
}
