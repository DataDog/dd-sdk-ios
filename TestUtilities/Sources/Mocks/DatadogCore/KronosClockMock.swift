/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogCore

public class KronosClockMock: KronosClockProtocol {
    public typealias FirstCompletion = (Date, TimeInterval) -> Void
    public typealias EndCompletion = (Date?, TimeInterval?) -> Void

    public var now: Date? {
        offset.map { .init(timeIntervalSinceNow: $0) }
    }

    public private(set) var currentPool: String? = nil
    public private(set) var first: FirstCompletion? = nil
    public private(set) var completion: EndCompletion? = nil
    private var offset: TimeInterval? = nil

    public init() {}

    public func update(offset: TimeInterval) {
        self.offset = offset

        if let first = first {
            first(.init(timeIntervalSinceNow: offset), offset)
            self.first = nil
        }
    }

    public func complete() {
        completion?(now, offset)
    }

    public func sync(
        from pool: String,
        samples: Int,
        first: FirstCompletion?,
        completion: EndCompletion?
    ) {
        self.currentPool = pool
        self.first = first
        self.completion = completion
    }
}
