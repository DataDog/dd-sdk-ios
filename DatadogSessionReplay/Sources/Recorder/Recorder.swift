/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

/// A type managing Session Replay recording.
internal protocol Recording {
    func captureNextRecord(_ recorderContext: Recorder.Context)
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
        let privacy: PrivacyLevel
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
            privacy: PrivacyLevel,
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
    /// Captures view tree snapshot (an intermediate representation of the view tree).
    private let viewTreeSnapshotProducer: ViewTreeSnapshotProducer
    /// Captures touch snapshot.
    private let touchSnapshotProducer: TouchSnapshotProducer
    /// Turns view tree snapshots into data models that will be uploaded to SR BE.
    private let snapshotProcessor: SnapshotProcessing
    /// Processes resources.
    private let resourceProcessor: ResourceProcessing
    /// Sends telemetry through sdk core.
    private let telemetry: Telemetry

    convenience init(
        snapshotProcessor: SnapshotProcessing,
        resourceProcessor: ResourceProcessing,
        telemetry: Telemetry
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
            uiApplicationSwizzler: try UIApplicationSwizzler(handler: touchSnapshotProducer),
            viewTreeSnapshotProducer: viewTreeSnapshotProducer,
            touchSnapshotProducer: touchSnapshotProducer,
            snapshotProcessor: snapshotProcessor,
            resourceProcessor: resourceProcessor,
            telemetry: telemetry
        )
    }

    init(
        uiApplicationSwizzler: UIApplicationSwizzler,
        viewTreeSnapshotProducer: ViewTreeSnapshotProducer,
        touchSnapshotProducer: TouchSnapshotProducer,
        snapshotProcessor: SnapshotProcessing,
        resourceProcessor: ResourceProcessing,
        telemetry: Telemetry
    ) {
        self.uiApplicationSwizzler = uiApplicationSwizzler
        self.viewTreeSnapshotProducer = viewTreeSnapshotProducer
        self.touchSnapshotProducer = touchSnapshotProducer
        self.snapshotProcessor = snapshotProcessor
        self.resourceProcessor = resourceProcessor
        self.telemetry = telemetry
        uiApplicationSwizzler.swizzle()
    }

    deinit {
        uiApplicationSwizzler.unswizzle()
    }

    // MARK: - Recording

    /// Initiates the capture of a next record.
    /// **Note**: This is called on the main thread.
    func captureNextRecord(_ recorderContext: Context) {
        do {
            guard let viewTreeSnapshot = try viewTreeSnapshotProducer.takeSnapshot(with: recorderContext) else {
                // There is nothing visible yet (i.e. the key window is not yet ready).
                return
            }
            let touchSnapshot = touchSnapshotProducer.takeSnapshot(context: recorderContext)
            snapshotProcessor.process(viewTreeSnapshot: viewTreeSnapshot, touchSnapshot: touchSnapshot)

            if !viewTreeSnapshot.resources.isEmpty {
                resourceProcessor.process(
                    resources: viewTreeSnapshot.resources,
                    context: .init(recorderContext.applicationID)
                )
            }
        } catch let error {
            telemetry.error("[SR] Failed to take snapshot", error: DDError(error: error))
        }
    }
}
#endif
