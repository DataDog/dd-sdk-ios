/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Simple `DateProvider` mock that returns given date.
public class DateProviderMock: DateProvider {
    public init(now: Date = Date()) {
        self.now = now
    }

    @ReadWriteLock
    public var now: Date
}

/// `DateProvider` mock returning consecutive dates in custom intervals, starting from given reference date.
public class RelativeDateProvider: DateProvider {
    private(set) var date: Date
    internal let timeInterval: TimeInterval
    private let queue = DispatchQueue(label: "queue-RelativeDateProvider-\(UUID().uuidString)")

    private init(date: Date, timeInterval: TimeInterval) {
        self.date = date
        self.timeInterval = timeInterval
    }

    public convenience init(using date: Date = Date()) {
        self.init(date: date, timeInterval: 0)
    }

    public convenience init(startingFrom referenceDate: Date = Date(), advancingBySeconds timeInterval: TimeInterval = 0) {
        self.init(date: referenceDate, timeInterval: timeInterval)
    }

    /// Returns current date and advances next date by `timeInterval`.
    public var now: Date {
        defer {
            queue.async {
                self.date.addTimeInterval(self.timeInterval)
            }
        }
        return queue.sync {
            return date
        }
    }

    /// Pushes time forward by given number of seconds.
    public func advance(bySeconds seconds: TimeInterval) {
        queue.async {
            self.date = self.date.addingTimeInterval(seconds)
        }
    }
}
