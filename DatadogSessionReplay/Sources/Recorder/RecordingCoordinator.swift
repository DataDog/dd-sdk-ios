/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import Datadog

internal protocol RecordingCoordination {
    var isSampled: Bool { get }
    var currentRUMContext: RUMContext? { get }
}

internal class RecordingCoordinator: RecordingCoordination {
    /// Schedules view tree captures.
    private let scheduler: Scheduler

    /// Notifies on RUM context changes through integration with `DatadogCore`.
    private let rumContextObserver: RUMContextObserver

    /// Updates other Features with SR context.
    private let contextPublisher: SRContextPublisher

    /// A flag that determines if SR will be sampled for the current session.
    /// Setting its value triggers the Context Publisher, which notifies
    /// other features whether recording has been triggered for the session.
    private(set) var isSampled = false {
        didSet {
            contextPublisher.setRecordingIsPending(isSampled)
        }
    }

    /// Last received RUM context (or `nil` if RUM session is not sampled).
    /// It's synchronized through `scheduler.queue` (main thread).
    private(set) var currentRUMContext: RUMContext? = nil

    init(
        scheduler: Scheduler,
        rumContextObserver: RUMContextObserver,
        contextPublisher: SRContextPublisher,
        sampler: Sampler
    ) {
        self.scheduler = scheduler
        self.rumContextObserver = rumContextObserver
        self.contextPublisher = contextPublisher

        contextPublisher.setRecordingIsPending(false)

        rumContextObserver.observe(on: scheduler.queue) { [weak self] rumContext in
            if self?.currentRUMContext?.ids.sessionID != rumContext?.ids.sessionID {
                self?.isSampled = sampler.sample()
            }
            self?.currentRUMContext = rumContext
        }
    }
}
