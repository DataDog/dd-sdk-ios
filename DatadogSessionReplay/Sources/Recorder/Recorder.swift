/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import Datadog

/// A type managing Session Replay recording.
internal protocol Recording {
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

        internal init(
            date: Date = Date(),
            privacy: SessionReplayPrivacy,
            rumContext: RUMContext
        ) {
            self.date = date
            self.privacy = privacy
            self.rumContext = rumContext
        }
    }

    /// Swizzles `UIApplication` for recording touch events.
    private let uiApplicationSwizzler: UIApplicationSwizzler

    /// Schedules view tree captures.
    private let scheduler: Scheduler
    /// Coordinates recording schedule
    private let recordingCoordinator: RecordingCoordination
    /// Captures view tree snapshot (an intermediate representation of the view tree).
    private let viewTreeSnapshotProducer: ViewTreeSnapshotProducer
    /// Captures touch snapshot.
    private let touchSnapshotProducer: TouchSnapshotProducer
    /// Turns view tree snapshots into data models that will be uploaded to SR BE.
    private let snapshotProcessor: Processing
    /// Current content recording policy for creating snapshots.
    private var currentPrivacy: SessionReplayPrivacy

    convenience init(
        configuration: SessionReplayConfiguration,
        rumContextObserver: RUMContextObserver,
        contextPublisher: SRContextPublisher,
        processor: Processing,
        scheduler: Scheduler = MainThreadScheduler(interval: 0.1)
    ) throws {
        let windowObserver = KeyWindowObserver()
        let viewTreeSnapshotProducer = WindowViewTreeSnapshotProducer(
            windowObserver: windowObserver,
            snapshotBuilder: ViewTreeSnapshotBuilder()
        )
        let touchSnapshotProducer = WindowTouchSnapshotProducer(
            windowObserver: windowObserver
        )

        let recordingCoordinator = RecordingCoordinator(
            scheduler: scheduler,
            rumContextObserver: rumContextObserver,
            contextPublisher: contextPublisher,
            sampler: Sampler(samplingRate: configuration.samplingRate)
        )

        self.init(
            configuration: configuration,
            rumContextObserver: rumContextObserver,
            uiApplicationSwizzler: try UIApplicationSwizzler(handler: touchSnapshotProducer),
            scheduler: scheduler,
            recordingCoordinator: recordingCoordinator,
            viewTreeSnapshotProducer: viewTreeSnapshotProducer,
            touchSnapshotProducer: touchSnapshotProducer,
            snapshotProcessor: processor
        )
    }

    init(
        configuration: SessionReplayConfiguration,
        rumContextObserver: RUMContextObserver,
        uiApplicationSwizzler: UIApplicationSwizzler,
        scheduler: Scheduler,
        recordingCoordinator: RecordingCoordination,
        viewTreeSnapshotProducer: ViewTreeSnapshotProducer,
        touchSnapshotProducer: TouchSnapshotProducer,
        snapshotProcessor: Processing
    ) {
        self.uiApplicationSwizzler = uiApplicationSwizzler
        self.scheduler = scheduler
        self.recordingCoordinator = recordingCoordinator
        self.viewTreeSnapshotProducer = viewTreeSnapshotProducer
        self.touchSnapshotProducer = touchSnapshotProducer
        self.snapshotProcessor = snapshotProcessor
        self.currentPrivacy = configuration.privacy

        scheduler.schedule { [weak self] in
            self?.captureNextRecord()
        }
        uiApplicationSwizzler.swizzle()
    }

    deinit {
        uiApplicationSwizzler.unswizzle()
    }

    // MARK: - Recording

    func change(privacy: SessionReplayPrivacy) {
        scheduler.queue.run {
            self.currentPrivacy = privacy
        }
    }

    /// Initiates the capture of a next record.
    /// **Note**: This is called on the main thread.
    private func captureNextRecord() {
        do {
            guard let rumContext = recordingCoordinator.currentRUMContext else {
                return
            }
            let recorderContext = Context(
                privacy: currentPrivacy,
                rumContext: rumContext
            )

            guard let viewTreeSnapshot = try viewTreeSnapshotProducer.takeSnapshot(with: recorderContext) else {
                // There is nothing visible yet (i.e. the key window is not yet ready).
                return
            }
            let touchSnapshot = touchSnapshotProducer.takeSnapshot(context: recorderContext)
            snapshotProcessor.process(viewTreeSnapshot: viewTreeSnapshot, touchSnapshot: touchSnapshot)
        } catch {
            print("Failed to capture the snapshot: \(error)") // TODO: RUMM-2410 Use `DD.logger` and / or `DD.telemetry`
        }
    }
}
