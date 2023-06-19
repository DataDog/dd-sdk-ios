/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import Datadog

internal protocol RecordingCoordination {
    /// Last received RUM context (or `nil` if RUM session is not sampled).
    var currentRUMContext: RUMContext? { get }

    /// Flag that determines weather SR should capture the next record.
    var shouldRecord: Bool { get }
}

/// Object is responsible for getting the RUM context, randomising the sampling rate,
/// starting/stopping the recording scheduler as needed and propagating `has_replay` to other features.
internal class RecordingCoordinator: RecordingCoordination {
    private(set) var currentRUMContext: RUMContext? = nil

    var shouldRecord: Bool {
        return isSampled && currentRUMContext?.ids.viewID != nil
    }

    private var isSampled: Bool = false

    init(
        scheduler: Scheduler,
        rumContextObserver: RUMContextObserver,
        srContextPublisher: SRContextPublisher,
        sampler: Sampler
    ) {
        srContextPublisher.setRecordingIsPending(false)
        scheduler.start()

        rumContextObserver.observe(on: scheduler.queue) { [weak self] rumContext in
            if self?.currentRUMContext?.ids.sessionID != rumContext?.ids.sessionID || self?.currentRUMContext == nil {
                let isSampled = sampler.sample()
                self?.isSampled = isSampled
            }
            self?.currentRUMContext = rumContext

            if self?.isSampled == true {
                scheduler.start()
            } else {
                scheduler.stop()
            }

            if let shouldRecord = self?.shouldRecord {
                srContextPublisher.setRecordingIsPending(shouldRecord)
            }
        }
    }
}
