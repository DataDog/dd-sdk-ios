/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
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

    /// Swizzles `UIApplication` for recording touch events.
    private let uiApplicationSwizzler: UIApplicationSwizzler

    /// Schedules view tree captures.
    private let scheduler: Scheduler
    /// Captures view tree snapshot (an intermediate representation of the view tree).
    private let viewTreeSnapshotProducer: ViewTreeSnapshotProducer
    /// Captures touch snapshot.
    private let touchSnapshotProducer: TouchSnapshotProducer
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

        self.init(
            configuration: configuration,
            rumContextObserver: rumContextObserver,
            uiApplicationSwizzler: try UIApplicationSwizzler(handler: touchSnapshotProducer),
            scheduler: scheduler,
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
        viewTreeSnapshotProducer: ViewTreeSnapshotProducer,
        touchSnapshotProducer: TouchSnapshotProducer,
        snapshotProcessor: Processing
    ) {
        self.uiApplicationSwizzler = uiApplicationSwizzler
        self.scheduler = scheduler
        self.viewTreeSnapshotProducer = viewTreeSnapshotProducer
        self.touchSnapshotProducer = touchSnapshotProducer
        self.snapshotProcessor = snapshotProcessor
        self.rumContextObserver = rumContextObserver
        self.currentPrivacy = configuration.privacy

        scheduler.schedule { [weak self] in
            self?.captureNextRecord()
        }

        rumContextObserver.observe(on: scheduler.queue) { [weak self] rumContext in
            self?.currentRUMContext = rumContext
        }

        uiApplicationSwizzler.swizzle()
    }

    deinit {
        uiApplicationSwizzler.unswizzle()
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
