/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal final class ExposureTracker {
    struct Exposure: Hashable {
        let targetingKey: String
        let flagKey: String
        let allocationKey: String
        let variationKey: String
    }

    private struct ExposureKey: Hashable {
        let targetingKey: String
        let flagKey: String

        init(_ exposure: Exposure) {
            self.targetingKey = exposure.targetingKey
            self.flagKey = exposure.flagKey
        }
    }

    private struct Assignment: Equatable {
        let allocationKey: String
        let variationKey: String

        init(_ exposure: Exposure) {
            self.allocationKey = exposure.allocationKey
            self.variationKey = exposure.variationKey
        }
    }

    // Keep enough latest assignments for the expected mobile case of 2 subjects x 2,500 flags.
    // A count-based LRU keeps this bounded without reintroducing NSCache's non-deterministic eviction.
    static let defaultCountLimit: Int = 5_000

    private var assignmentsByExposureKey: [ExposureKey: Assignment] = [:]
    private var exposureKeysByRecency: [ExposureKey] = []
    private let countLimit: Int
    private let lock: NSLocking

    init(
        countLimit: Int = defaultCountLimit,
        lock: NSLocking = NSLock()
    ) {
        self.countLimit = countLimit
        self.lock = lock
    }

    func track(_ exposure: Exposure) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let key = ExposureKey(exposure)
        let assignment = Assignment(exposure)
        guard assignmentsByExposureKey[key] != assignment else {
            markRecentlyUsed(key)
            return false
        }

        assignmentsByExposureKey[key] = assignment
        markRecentlyUsed(key)
        evictLeastRecentlyUsedEntriesIfNeeded()
        return true
    }

    private func markRecentlyUsed(_ key: ExposureKey) {
        exposureKeysByRecency.removeAll { $0 == key }
        exposureKeysByRecency.append(key)
    }

    private func evictLeastRecentlyUsedEntriesIfNeeded() {
        while assignmentsByExposureKey.count > countLimit, !exposureKeysByRecency.isEmpty {
            assignmentsByExposureKey.removeValue(forKey: exposureKeysByRecency.removeFirst())
        }
    }
}
