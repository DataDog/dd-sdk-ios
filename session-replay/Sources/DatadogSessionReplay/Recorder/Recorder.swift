/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// The main engine and the heart of Session Replay.
///
/// It instruments running application by observing current window(s) and
/// captures intermediate representation of the view hierarchy. This representation
/// is later passed to `Processor` and turned into wireframes uploaded to the BE.
internal class Recorder {
    let scheduler: Scheduler

    convenience init() {
        self.init(
            scheduler: MainThreadScheduler(interval: 0.2)
        )
    }

    init(scheduler: Scheduler) {
        self.scheduler = scheduler
    }

    func start() {
        scheduler.schedule {
            print("⏰ \(UUID().uuidString)")
        }
        scheduler.start()
    }

    func stop() {
        scheduler.stop()
    }
}
