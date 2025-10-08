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

    private class ExposureBox: NSObject {
        let value: Exposure

        init(_ value: Exposure) {
            self.value = value
        }

        override var hash: Int {
            value.hashValue
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? ExposureBox else {
                return false
            }
            return value == other.value
        }
    }

    private let cache = NSCache<ExposureBox, NSNumber>()
    private let sentinel = NSNumber(value: true)

    init(countLimit: Int = 1_000) {
        self.cache.countLimit = countLimit
    }

    func contains(_ exposure: Exposure) -> Bool {
        cache.object(forKey: .init(exposure)) != nil
    }

    func insert(_ exposure: Exposure) {
        cache.setObject(sentinel, forKey: .init(exposure))
    }
}
