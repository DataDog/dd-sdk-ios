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
@_spi(Internal)
public class Recorder: Recording {
    /// The context of recording next snapshot.
    public struct Context: Equatable {
        /// The content recording policy from the moment of requesting snapshot.
        public let privacy: SessionReplayPrivacyLevel
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
    /// Processes resources on a background thread.
    private let resourceProcessor: ResourceProcessing
    /// Sends telemetry through sdk core.
    private let telemetry: Telemetry
    /// The sampler for internal telemetry.
    private let telemetrySampler: Sampler

    convenience init(
        snapshotProcessor: SnapshotProcessing,
        resourceProcessor: ResourceProcessing,
        telemetry: Telemetry,
        additionalNodeRecorders: [NodeRecorder]
    ) throws {
        let windowObserver = KeyWindowObserver()
        let viewTreeSnapshotProducer = WindowViewTreeSnapshotProducer(
            windowObserver: windowObserver,
            snapshotBuilder: ViewTreeSnapshotBuilder(additionalNodeRecorders: additionalNodeRecorders)
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
            telemetry: telemetry,
            telemetrySampler: Sampler(samplingRate: 0.005) // 0.5% of calls
        )
    }

    init(
        uiApplicationSwizzler: UIApplicationSwizzler,
        viewTreeSnapshotProducer: ViewTreeSnapshotProducer,
        touchSnapshotProducer: TouchSnapshotProducer,
        snapshotProcessor: SnapshotProcessing,
        resourceProcessor: ResourceProcessing,
        telemetry: Telemetry,
        telemetrySampler: Sampler
    ) {
        self.uiApplicationSwizzler = uiApplicationSwizzler
        self.viewTreeSnapshotProducer = viewTreeSnapshotProducer
        self.touchSnapshotProducer = touchSnapshotProducer
        self.snapshotProcessor = snapshotProcessor
        self.resourceProcessor = resourceProcessor
        self.telemetry = telemetry
        self.telemetrySampler = telemetrySampler
        uiApplicationSwizzler.swizzle()
    }

    deinit {
        uiApplicationSwizzler.unswizzle()
    }

    // MARK: - Recording

    /// Initiates the capture of a next record.
    /// **Note**: This is called on the main thread.
    func captureNextRecord(_ recorderContext: Context) {
        let methodCallTrace = telemetry.startMethodCall(
            operationName: MethodCallConstants.captureRecordOperationName,
            callerClass: MethodCallConstants.className,
            samplingRate: MethodCallConstants.captureRecordSampling // Effectively 3% * 15% = 0.45% of calls
        )
        var isSuccesful = true
        do {
            guard let viewTreeSnapshot = try viewTreeSnapshotProducer.takeSnapshot(with: recorderContext) else {
                // There is nothing visible yet (i.e. the key window is not yet ready).
                return
            }
            let touchSnapshot = touchSnapshotProducer.takeSnapshot(context: recorderContext)
            snapshotProcessor.process(viewTreeSnapshot: viewTreeSnapshot, touchSnapshot: touchSnapshot)

            resourceProcessor.process(
                resources: viewTreeSnapshot.resources,
                context: .init(recorderContext.applicationID)
            )
        } catch let error {
            isSuccesful = false
            telemetry.error("[SR] Failed to take snapshot", error: DDError(error: error))
        }
        telemetry.stopMethodCall(methodCallTrace, isSuccessful: isSuccesful)
    }

    private enum MethodCallConstants {
        static let captureRecordOperationName = "Capture Record"
        static let className = "Recorder"
        static let captureRecordSampling: Float = 15.0
    }
}
#endif
