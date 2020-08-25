/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal extension Thread {
    enum SleepDuration {
        case short
        case medium
        case long

        var timeInterval: TimeInterval {
            switch self {
            case .short: return TimeInterval.random(in: 0...0.1)
            case .medium: return TimeInterval.random(in: 0.05...0.35)
            case .long: return TimeInterval.random(in: 0.2...0.5)
            }
        }
    }

    static func sleep(for duration: SleepDuration) {
        sleep(forTimeInterval: duration.timeInterval)
    }
}
