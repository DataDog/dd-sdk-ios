/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

/// Object is responsible for getting the RUM context, randomising the sampling rate,
/// starting/stopping the recording scheduler as needed and propagating `has_replay` to other features.
internal class RecordingCoordinator {
    let recorder: Recording
    let scheduler: Scheduler
    let sampler: Sampler
    let privacy: PrivacyLevel
    let srContextPublisher: SRContextPublisher

    private var currentRUMContext: RUMContext? = nil
    private var isSampled = false

    init(
        scheduler: Scheduler,
        privacy: PrivacyLevel,
        rumContextObserver: RUMContextObserver,
        srContextPublisher: SRContextPublisher,
        recorder: Recording,
        sampler: Sampler
    ) {
        self.recorder = recorder
        self.scheduler = scheduler
        self.sampler = sampler
        self.privacy = privacy
        self.srContextPublisher = srContextPublisher

        srContextPublisher.setHasReplay(false)

        scheduler.schedule { [weak self] in self?.captureNextRecord() }
        scheduler.start()

        rumContextObserver.observe(on: scheduler.queue) { [weak self] in self?.onRUMContextChanged(rumContext: $0) }
    }

    private func onRUMContextChanged(rumContext: RUMContext?) {
        if currentRUMContext?.ids.sessionID != rumContext?.ids.sessionID || currentRUMContext == nil {
            isSampled = sampler.sample()
        }

        currentRUMContext = rumContext

        if isSampled {
            scheduler.start()
        } else {
            scheduler.stop()
        }

        srContextPublisher.setHasReplay(
            isSampled == true && currentRUMContext?.ids.viewID != nil
        )
    }

    private func captureNextRecord() {
        guard let rumContext = currentRUMContext,
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
        recorder.captureNextRecord(recorderContext)
    }
}
#endif
