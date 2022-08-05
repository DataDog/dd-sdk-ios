/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// The main engine and the heart beat of Session Replay.
///
/// It instruments running application by observing current window(s) and
/// captures intermediate representation of the view hierarchy. This representation
/// is later passed to `Processor` and turned into wireframes uploaded to the BE.
internal class Recorder {
    /// Schedules view tree captures.
    let scheduler: Scheduler
    /// Captures view tree snapshot (an intermediate representation of the view tree).
    let snapshotProducer: ViewTreeSnapshotProducer
    /// Turns view tree snapshots into data models that will be uploaded to SR BE.
    let snapshotProcessor: ViewTreeSnapshotProcessor

    convenience init() {
        self.init(
            scheduler: MainThreadScheduler(interval: 0.2),
            snapshotProducer: WindowSnapshotProducer(
                windowObserver: KeyWindowObserver()
            ),
            snapshotProcessor: Processor()
        )
    }

    init(
        scheduler: Scheduler,
        snapshotProducer: ViewTreeSnapshotProducer,
        snapshotProcessor: ViewTreeSnapshotProcessor
    ) {
        self.scheduler = scheduler
        self.snapshotProducer = snapshotProducer
        self.snapshotProcessor = snapshotProcessor

        scheduler.schedule { [weak self] in
            self?.captureNextRecord()
        }
    }

    func start() {
        scheduler.start()
    }

    func stop() {
        scheduler.stop()
    }

    /// Initiates the capture of a next record.
    /// **Note**: This is called on the main thread.
    private func captureNextRecord() {
        guard let snapshot = snapshotProducer.takeSnapshot() else {
            print("Failed to take the snapshot of current window") // TODO: RUMM-2410 Use `DD.logger` and / or `DD.telemetry`
            return
        }

        snapshotProcessor.process(snapshot: snapshot)
    }
}
