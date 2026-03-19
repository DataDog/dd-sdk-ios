/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import Foundation
import XCTest

/// Generic utility class to safely manage context data for C callbacks
/// This avoids the "may contain an object reference" warning when passing structs to C
final class CCallbackContext<T> {
    private let box: UnsafeMutablePointer<T>

    init(_ initialData: T) {
        self.box = UnsafeMutablePointer<T>.allocate(capacity: 1)
        self.box.initialize(to: initialData)
    }

    deinit {
        box.deinitialize(count: 1)
        box.deallocate()
    }

    /// Get the unsafe raw pointer for passing to C functions
    var rawPointer: UnsafeMutableRawPointer { UnsafeMutableRawPointer(box) }

    /// Access the current data
    var value: T {
        get { return box.pointee }
        set { box.pointee = newValue }
    }

    /// Static method to safely extract context from C callback userData
    static func fromContextPointer(_ ctx: UnsafeMutableRawPointer?) -> T? {
        guard let ctx else {
            return nil
        }
        return ctx.assumingMemoryBound(to: T.self).pointee
    }

    /// Static method to safely extract and modify context from C callback userData
    static func withContextPointer<R>(_ ctx: UnsafeMutableRawPointer?, _ body: (inout T) -> R) -> R? {
        guard let ctx else {
            return nil
        }
        let pointer = ctx.assumingMemoryBound(to: T.self)
        return body(&pointer.pointee)
    }
}
#endif // !os(watchOS)
