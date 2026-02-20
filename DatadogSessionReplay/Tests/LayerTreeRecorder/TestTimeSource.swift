/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

@testable import DatadogSessionReplay

@available(iOS 13.0, tvOS 13.0, *)
struct ConstantTimeSource: TimeSource {
    let now: TimeInterval
}

@available(iOS 13.0, tvOS 13.0, *)
final class SequenceTimeSource: TimeSource {
    private let values: [TimeInterval]
    private var index = 0

    init(_ values: [TimeInterval]) {
        self.values = values
    }

    var now: TimeInterval {
        guard !values.isEmpty else {
            return 0
        }

        let current = values[min(index, values.count - 1)]
        if index < values.count - 1 {
            index += 1
        }
        return current
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension TimeSource where Self == ConstantTimeSource {
    static func constant(_ value: TimeInterval) -> Self {
        .init(now: value)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension TimeSource where Self == SequenceTimeSource {
    static func sequence(_ values: [TimeInterval]) -> Self {
        .init(values)
    }
}
#endif
