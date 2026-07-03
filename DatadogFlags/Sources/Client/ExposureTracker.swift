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

    private final class ExposureKey: NSObject {
        let targetingKey: String
        let flagKey: String

        init(_ exposure: Exposure) {
            self.targetingKey = exposure.targetingKey
            self.flagKey = exposure.flagKey
        }

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(targetingKey)
            hasher.combine(flagKey)
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? ExposureKey else {
                return false
            }

            return targetingKey == other.targetingKey && flagKey == other.flagKey
        }
    }

    private final class Assignment {
        let allocationKey: String
        let variationKey: String

        init(_ exposure: Exposure) {
            self.allocationKey = exposure.allocationKey
            self.variationKey = exposure.variationKey
        }

        func isEqual(to other: Assignment) -> Bool {
            allocationKey == other.allocationKey && variationKey == other.variationKey
        }
    }

    // Keep enough latest assignments for the expected mobile case of 2 subjects x 2,500 flags.
    // Normal flag keys are typically tens of characters, so entry count is easier to reason about
    // than object-size estimates.
    static let defaultCountLimit: Int = 5_000

    private let assignmentsByExposureKey = NSCache<ExposureKey, Assignment>()
    private let lock: NSLocking

    init(
        countLimit: Int = defaultCountLimit,
        lock: NSLocking = NSLock()
    ) {
        self.lock = lock
        self.assignmentsByExposureKey.countLimit = countLimit
    }

    func track(_ exposure: Exposure) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let key = ExposureKey(exposure)
        let assignment = Assignment(exposure)
        guard assignmentsByExposureKey.object(forKey: key)?.isEqual(to: assignment) != true else {
            return false
        }

        assignmentsByExposureKey.setObject(assignment, forKey: key)
        return true
    }
}
