/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal class FrameDurationInstrument {
    private var runLoopObserver: CFRunLoopObserver!

    init() {
        runLoopObserver = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.allActivities.rawValue, //CFRunLoopActivity.entry.rawValue | CFRunLoopActivity.exit.rawValue,
            true,
            0
        ) { [weak self] observer, activity in self?.step(observer: observer, activity: activity) }
    }

    func start() { CFRunLoopAddObserver(CFRunLoopGetMain(), runLoopObserver, CFRunLoopMode.commonModes) }
    func stop() { CFRunLoopRemoveObserver(CFRunLoopGetMain(), runLoopObserver, CFRunLoopMode.commonModes) }

    var previousActivity: (CFRunLoopActivity, Date)? = nil

    private func step(observer: CFRunLoopObserver?, activity: CFRunLoopActivity) {
        let now = Date()
        defer { previousActivity = (activity, now) }

        if let previous = previousActivity {
            let duration = now.timeIntervalSince(previous.1)
            print("⏱️ run loop: \(previous.0.pretty) → \(activity.pretty) [\(duration.toMs)]")
        }
    }
}

private extension CFRunLoopActivity {
    var pretty: String {
        switch self {
        case .entry: return "entry"
        case .beforeTimers: return "beforeTimers"
        case .beforeSources: return "beforeSources"
        case .beforeWaiting: return "beforeWaiting"
        case .afterWaiting: return "afterWaiting"
        case .exit: return "exit"
        case .allActivities: return "allActivities"
        default: return "???"
        }
    }
}

internal extension TimeInterval {
    var toMs: String {
        let value = (self * Double(1_000) * Double(1_000)).rounded() / Double(1_000)
        return "\(value)ms"
    }
}
