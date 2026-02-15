/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import QuartzCore
import Foundation

@available(iOS 13.0, tvOS 13.0, *)
extension CALayer {
    @MainActor var replayID: Int64 {
        if let value = objc_getAssociatedObject(self, &ReplayID.key) as? Int64 {
            return value
        }

        let value = ReplayID.generator.next()
        objc_setAssociatedObject(self, &ReplayID.key, value, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        return value
    }
}

@available(iOS 13.0, tvOS 13.0, *)
internal struct ReplayIDGenerator: Sendable {
    var next: @Sendable @MainActor () -> Int64

    @MainActor static var autoincrementing: Self {
        var currentID: Int64 = 0
        let maxID = Int64(Int32.max)
        return ReplayIDGenerator {
            let id = currentID
            currentID = currentID < maxID ? (currentID + 1) : 0
            return id
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayer {
    @MainActor
    static func withReplayIDGenerator<R>(
        _ generator: ReplayIDGenerator,
        operation: () throws -> R
    ) rethrows -> R {
        try ReplayID.Context.$generator.withValue(generator) {
            try operation()
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayer {
    fileprivate enum ReplayID {
        enum Context {
            @TaskLocal @MainActor static var generator: ReplayIDGenerator?
        }

        static var key: UInt8 = 0

        @MainActor static var generator: ReplayIDGenerator {
            Context.generator ?? sharedGenerator
        }

        @MainActor static let sharedGenerator: ReplayIDGenerator = .autoincrementing
    }
}
#endif
