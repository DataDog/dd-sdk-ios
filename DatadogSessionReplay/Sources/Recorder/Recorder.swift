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
        let accessibilityOptions: SessionReplayAccessibilityOptions
        /// The RUM context from the moment of requesting snapshot.
        let rumContext: RUMContext
    }

    /// Swizzles `UIApplication` for recording touch events.
    private let uiApplicationSwizzler: UIApplicationSwizzler
    private let accessibilitySwizzler: UIAccessibilitySwizzler

    /// Schedules view tree captures.
    private let scheduler: Scheduler
    /// Captures view tree snapshot (an intermediate representation of the view tree).
    private let viewTreeSnapshotProducer: ViewTreeSnapshotProducer
    /// Captures touch snapshot.
    private let touchSnapshotProducer: TouchSnapshotProducer
    private let accessibilitySnapshotProducer: AccessibilitySnapshotProducer
    /// Turns view tree snapshots into data models that will be uploaded to SR BE.
    private let snapshotProcessor: Processing

    /// Notifies on RUM context changes through integration with `DatadogCore`.
    private let rumContextObserver: RUMContextObserver
    /// Last received RUM context (or `nil` if RUM session is not sampled).
    /// It's synchronized through `scheduler.queue` (main thread).
    private var currentRUMContext: RUMContext?
    /// Current content recording policy for creating snapshots.
    private var currentPrivacy: SessionReplayPrivacy
    private var currentAccessibilityOptions: SessionReplayAccessibilityOptions

    convenience init(
        configuration: SessionReplayConfiguration,
        rumContextObserver: RUMContextObserver,
        processor: Processing,
        scheduler: Scheduler = MainThreadScheduler(interval: 0.1)
    ) throws {
        let windowObserver = KeyWindowObserver()
        let viewTreeSnapshotBuilder = ViewTreeSnapshotBuilder()
        let viewTreeSnapshotProducer = WindowViewTreeSnapshotProducer(
            windowObserver: windowObserver,
            snapshotBuilder: viewTreeSnapshotBuilder
        )
        let touchSnapshotProducer = WindowTouchSnapshotProducer(
            windowObserver: windowObserver
        )
        let accessibilitySnapshotProducer = AccessibilitySnapshotProducer(
            idsGenerator: viewTreeSnapshotBuilder.accessibilityIDsGenerator,
            windowObserver: windowObserver
        )

        self.init(
            configuration: configuration,
            rumContextObserver: rumContextObserver,
            uiApplicationSwizzler: try UIApplicationSwizzler(handler: touchSnapshotProducer),
            accessibilitySwizzler: try UIAccessibilitySwizzler(),
            scheduler: scheduler,
            viewTreeSnapshotProducer: viewTreeSnapshotProducer,
            touchSnapshotProducer: touchSnapshotProducer,
            accessibilitySnapshotProducer: accessibilitySnapshotProducer,
            snapshotProcessor: processor
        )
    }

    init(
        configuration: SessionReplayConfiguration,
        rumContextObserver: RUMContextObserver,
        uiApplicationSwizzler: UIApplicationSwizzler,
        accessibilitySwizzler: UIAccessibilitySwizzler,
        scheduler: Scheduler,
        viewTreeSnapshotProducer: ViewTreeSnapshotProducer,
        touchSnapshotProducer: TouchSnapshotProducer,
        accessibilitySnapshotProducer: AccessibilitySnapshotProducer,
        snapshotProcessor: Processing
    ) {
        self.uiApplicationSwizzler = uiApplicationSwizzler
        self.accessibilitySwizzler = accessibilitySwizzler
        self.scheduler = scheduler
        self.viewTreeSnapshotProducer = viewTreeSnapshotProducer
        self.touchSnapshotProducer = touchSnapshotProducer
        self.snapshotProcessor = snapshotProcessor
        self.accessibilitySnapshotProducer = accessibilitySnapshotProducer
        self.rumContextObserver = rumContextObserver
        self.currentPrivacy = configuration.privacy
        self.currentAccessibilityOptions = configuration.accessibilityOptions

        scheduler.schedule { [weak self] in
            self?.captureNextRecord()
        }

        rumContextObserver.observe(on: scheduler.queue) { [weak self] rumContext in
            self?.currentRUMContext = rumContext
        }

        uiApplicationSwizzler.swizzle()
        accessibilitySwizzler.swizzle()
    }

    deinit {
        uiApplicationSwizzler.unswizzle()
        accessibilitySwizzler.unswizzle()
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
                accessibilityOptions: currentAccessibilityOptions,
                rumContext: rumContext
            )

            guard let viewTreeSnapshot = try viewTreeSnapshotProducer.takeSnapshot(with: recorderContext) else {
                // There is nothing visible yet (i.e. the key window is not yet ready).
                return
            }
            let touchSnapshot = touchSnapshotProducer.takeSnapshot(context: recorderContext)
            let accessibilitySnapshot = accessibilitySnapshotProducer.takeSnapshot(context: recorderContext)
            snapshotProcessor.process(
                viewTreeSnapshot: viewTreeSnapshot,
                touchSnapshot: touchSnapshot,
                accessibilitySnapshot: accessibilitySnapshot
            )
        } catch {
            print("Failed to capture the snapshot: \(error)") // TODO: RUMM-2410 Use `DD.logger` and / or `DD.telemetry`
        }
    }
}
