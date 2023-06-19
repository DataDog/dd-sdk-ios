/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import Datadog

internal protocol RecordingCoordination {
    /// Last received RUM context (or `nil` if RUM session is not sampled).
    /// It's synchronized through `scheduler.queue` (main thread).
    var currentRUMContext: RUMContext? { get }
    /// Flag that determines if SR should be sampled.
    var isSampled: Bool { get }
}

/// Object is responsible for getting the RUM context, randomising the sampling rate,
/// starting the recording scheduler and propagating `has_replay` to other features.
internal class RecordingCoordinator: RecordingCoordination {
    private(set) var currentRUMContext: RUMContext? = nil
    private(set) var isSampled: Bool = false
    init(
        scheduler: Scheduler,
        rumContextObserver: RUMContextObserver,
        srContextPublisher: SRContextPublisher,
        sampler: Sampler
    ) {
        scheduler.start()
        srContextPublisher.setRecordingIsPending(false)

        rumContextObserver.observe(on: scheduler.queue) { [weak self] rumContext in
            if self?.currentRUMContext?.ids.sessionID != rumContext?.ids.sessionID || self?.currentRUMContext == nil {
                let isSampled = sampler.sample() && rumContext != nil
                srContextPublisher.setRecordingIsPending(isSampled)
                self?.isSampled = isSampled && rumContext != nil
            }
            self?.currentRUMContext = rumContext
        }
    }
}
