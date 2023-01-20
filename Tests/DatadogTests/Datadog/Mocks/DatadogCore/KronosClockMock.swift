/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@testable import Datadog

internal class KronosClockMock: KronosClockProtocol {
    typealias FirstCompletion = (Date, TimeInterval) -> Void
    typealias EndCompletion = (Date?, TimeInterval?) -> Void

    var now: Date? {
        offset.map { .init(timeIntervalSinceNow: $0) }
    }

    private(set) var currentPool: String? = nil
    private(set) var first: FirstCompletion? = nil
    private(set) var completion: EndCompletion? = nil
    private var offset: TimeInterval? = nil

    func update(offset: TimeInterval) {
        self.offset = offset

        if let first = first {
            first(.init(timeIntervalSinceNow: offset), offset)
            self.first = nil
        }
    }

    func complete() {
        completion?(now, offset)
    }

    func sync(
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
