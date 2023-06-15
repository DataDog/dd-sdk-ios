/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import Datadog

internal protocol RecordingCoordination {
    var currentRUMContext: RUMContext? { get }
}

/// Object is responsible for getting the RUM context, randomising the sampling rate,
/// starting/stopping the recording scheduler as needed and propagating `has_replay` to other features.
internal class RecordingCoordinator: RecordingCoordination {
    /// Last received RUM context (or `nil` if RUM session is not sampled).
    /// It's synchronized through `scheduler.queue` (main thread).
    private(set) var currentRUMContext: RUMContext? = nil

    init(
        scheduler: Scheduler,
        rumContextObserver: RUMContextObserver,
        contextPublisher: SRContextPublisher,
        sampler: Sampler
    ) {
        contextPublisher.setRecordingIsPending(false)

        rumContextObserver.observe(on: scheduler.queue) { [weak self] rumContext in
            if self?.currentRUMContext?.ids.sessionID != rumContext?.ids.sessionID || self?.currentRUMContext == nil {
                let isSampled = sampler.sample() && rumContext != nil
                contextPublisher.setRecordingIsPending(isSampled)
                if isSampled {
                    scheduler.start()
                } else {
                    scheduler.stop()
                }
            }
            self?.currentRUMContext = rumContext
        }
    }
}
