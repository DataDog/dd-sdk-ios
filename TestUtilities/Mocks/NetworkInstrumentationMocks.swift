/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension TraceID {
    public static func mockAny() -> TraceID {
        return TraceID(rawValue: .mockAny())
    }

    public static func mock(_ rawValue: UInt64) -> TraceID {
        return TraceID(rawValue: rawValue)
    }
}

public class RelativeTracingUUIDGenerator: TraceIDGenerator {
    private(set) var uuid: TraceID
    internal let count: UInt64
    private let queue = DispatchQueue(label: "queue-RelativeTracingUUIDGenerator-\(UUID().uuidString)")

    public init(startingFrom uuid: TraceID, advancingByCount count: UInt64 = 1) {
        self.uuid = uuid
        self.count = count
    }

    public func generate() -> TraceID {
        return queue.sync {
            defer { uuid = uuid + count }
            return uuid
        }
    }
}

private func + (lhs: TraceID, rhs: UInt64) -> TraceID {
    return TraceID(rawValue: (UInt64(String(lhs)) ?? 0) + rhs)
}
