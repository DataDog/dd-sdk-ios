/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal protocol TimeBank {
    mutating func consume(interval: TimeInterval)

    mutating func recharge(timestamp: Date)

    var isPositive: Bool { get }
}

internal struct NOPTimeBank: TimeBank {
    /// no-op
    func consume(interval: TimeInterval) { }
    /// no-op
    func recharge(timestamp: Date) { }
    /// no-op: returns `true`
    var isPositive: Bool { true }
}

internal final class RecordingTimeBank: TimeBank {
    private let factor: TimeInterval
    private let maxBalance: TimeInterval

    private var balance: TimeInterval
    private var lastUpdateDate: Date = .distantPast

    init(balance: TimeInterval = 0.1, interval: TimeInterval = 1) {
        self.maxBalance = balance
        self.balance = balance
        self.factor = balance / interval
    }

    func consume(interval: TimeInterval) {
        balance -= interval
    }

    func recharge(timestamp: Date) {
        balance += timestamp.timeIntervalSince(lastUpdateDate) * factor
        balance = min(balance, maxBalance)
        lastUpdateDate = timestamp
    }

    var isPositive: Bool { balance >= 0 }
}
