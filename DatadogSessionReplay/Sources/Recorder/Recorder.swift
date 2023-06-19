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
        /// The content recording policy from the moment of requesting snapshot.
        let privacy: SessionReplayPrivacy
        /// Current RUM application ID - standard UUID string, lowecased.
        let applicationID: String
        /// Current RUM session ID - standard UUID string, lowecased.
        let sessionID: String
        /// Current RUM view ID - standard UUID string, lowecased.
        let viewID: String
        /// Current view related server time offset
        let viewServerTimeOffset: TimeInterval?
        /// The time of requesting this snapshot.
        let date: Date

        internal init(
            privacy: SessionReplayPrivacy,
            applicationID: String,
            sessionID: String,
            viewID: String,
            viewServerTimeOffset: TimeInterval?,
            date: Date = Date()
        ) {
            self.privacy = privacy
            self.applicationID = applicationID
            self.sessionID = sessionID
            self.viewID = viewID
            self.viewServerTimeOffset = viewServerTimeOffset
            self.date = date
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
        recordingCoordinator: RecordingCoordination,
        processor: Processing,
        scheduler: Scheduler
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
            guard recordingCoordinator.shouldRecord else {
                return
            }
            guard let rumContext = recordingCoordinator.currentRUMContext,
                  let viewID = rumContext.ids.viewID else {
                return
            }
            let recorderContext = Context(
                privacy: currentPrivacy,
                applicationID: rumContext.ids.applicationID,
                sessionID: rumContext.ids.sessionID,
                viewID: viewID,
                viewServerTimeOffset: rumContext.viewServerTimeOffset
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
