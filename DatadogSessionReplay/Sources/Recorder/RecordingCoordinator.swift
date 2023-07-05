/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import Datadog

/// Object is responsible for getting the RUM context, randomising the sampling rate,
/// starting/stopping the recording scheduler as needed and propagating `has_replay` to other features.
internal class RecordingCoordinator {
    private let recorder: Recording

    private var currentRUMContext: RUMContext? = nil
    private var isSampled = false

    init(
        scheduler: Scheduler,
        privacy: SessionReplayPrivacy,
        rumContextObserver: RUMContextObserver,
        srContextPublisher: SRContextPublisher,
        recorder: Recording,
        sampler: Sampler
    ) {
        self.recorder = recorder
        srContextPublisher.setHasReplay(false)

        scheduler.schedule { [weak self] in
            guard let rumContext = self?.currentRUMContext,
                  let viewID = rumContext.ids.viewID else {
                return
            }
            let recorderContext = Recorder.Context(
                privacy: privacy,
                applicationID: rumContext.ids.applicationID,
                sessionID: rumContext.ids.sessionID,
                viewID: viewID,
                viewServerTimeOffset: rumContext.viewServerTimeOffset
            )
            self?.recorder.captureNextRecord(recorderContext)
        }

        scheduler.start()

        rumContextObserver.observe(on: scheduler.queue) { [weak self] rumContext in
            if self?.currentRUMContext?.ids.sessionID != rumContext?.ids.sessionID || self?.currentRUMContext == nil {
                self?.isSampled = sampler.sample()
            }

            self?.currentRUMContext = rumContext

            if self?.isSampled == true {
                scheduler.start()
            } else {
                scheduler.stop()
            }

            srContextPublisher.setHasReplay(
                self?.isSampled == true && self?.currentRUMContext?.ids.viewID != nil
            )
        }
    }
}
