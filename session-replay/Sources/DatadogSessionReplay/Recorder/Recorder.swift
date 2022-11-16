/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Datadog

/// A type managing Session Replay recording.
internal protocol Recording {
    func start()
    func stop()
    func change(privacy: SessionReplayPrivacy)
}

/// The main engine and the heart beat of Session Replay.
///
/// It instruments running application by observing current window(s) and
/// captures intermediate representation of the view hierarchy. This representation
/// is later passed to `Processor` and turned into wireframes uploaded to the BE.
internal class Recorder: Recording {
    /// The context of recording next snapshot.
    struct Context: Equatable {
        /// The time of requesting this snapshot.
        let date: Date
        /// The content recording policy from the moment of requesting snapshot.
        let privacy: SessionReplayPrivacy
        /// The RUM context from the moment of requesting snapshot.
        let rumContext: RUMContext
    }

    /// Schedules view tree captures.
    private let scheduler: Scheduler
    /// Captures view tree snapshot (an intermediate representation of the view tree).
    private let snapshotProducer: ViewTreeSnapshotProducer
    /// Turns view tree snapshots into data models that will be uploaded to SR BE.
    private let snapshotProcessor: Processing

    /// Notifies on RUM context changes through integration with `DatadogCore`.
    private let rumContextObserver: RUMContextObserver
    /// Last received RUM context (or `nil` if RUM session is not sampled).
    /// It's synchronized through `scheduler.queue` (main thread).
    private var currentRUMContext: RUMContext?
    /// Current content recording policy for creating snapshots.
    private var currentPrivacy: SessionReplayPrivacy

    convenience init(
        configuration: SessionReplayConfiguration,
        rumContextObserver: RUMContextObserver,
        processor: Processing
    ) {
        self.init(
            configuration: configuration,
            rumContextObserver: rumContextObserver,
            scheduler: MainThreadScheduler(interval: 0.1),
            snapshotProducer: WindowSnapshotProducer(
                windowObserver: KeyWindowObserver(),
                snapshotBuilder: ViewTreeSnapshotBuilder()
            ),
            snapshotProcessor: processor
        )
    }

    init(
        configuration: SessionReplayConfiguration,
        rumContextObserver: RUMContextObserver,
        scheduler: Scheduler,
        snapshotProducer: ViewTreeSnapshotProducer,
        snapshotProcessor: Processing
    ) {
        self.scheduler = scheduler
        self.snapshotProducer = snapshotProducer
        self.snapshotProcessor = snapshotProcessor
        self.rumContextObserver = rumContextObserver
        self.currentPrivacy = configuration.privacy

        scheduler.schedule { [weak self] in
            self?.captureNextRecord()
        }

        rumContextObserver.observe(on: scheduler.queue) { [weak self] rumContext in
            self?.currentRUMContext = rumContext
        }
    }

    // MARK: - Recording

    func start() {
        scheduler.start()
    }

    func stop() {
        scheduler.stop()
    }

    func change(privacy: SessionReplayPrivacy) {
        scheduler.queue.run {
            self.currentPrivacy = privacy
        }
    }

    /// Initiates the capture of a next record.
    /// **Note**: This is called on the main thread.
    private func captureNextRecord() {
        do {
            guard let rumContext = currentRUMContext else {
                // The RUM context was not yet received or current RUM session is not sampled.
                return
            }

            let recorderContext = Context(
                date: Date(), // TODO: RUMM-2688 Synchronize SR snapshot timestamps with current RUM time (+ NTP offset)
                privacy: currentPrivacy,
                rumContext: rumContext
            )

            guard let snapshot = try snapshotProducer.takeSnapshot(with: recorderContext) else {
                // There is nothing visible yet (i.e. the key window is not yet ready).
                return
            }

            snapshotProcessor.process(snapshot: snapshot)
        } catch {
            print("Failed to capture the snapshot: \(error)") // TODO: RUMM-2410 Use `DD.logger` and / or `DD.telemetry`
        }
    }
}
