/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */
import DatadogInternal
import UIKit

/// Orchestrates the process of triggering next snapshot recording.
/// It has 2 recording triggers: `layoutSubviews` and touch event, which are achieved by using swizzling.
internal class RecordingTrigger: UIViewHandler, UIEventHandler {
    private var uiViewSwizzler: UIViewSwizzler? = nil
    private var uiApplicationSwizzler: UIApplicationSwizzler? = nil

    private weak var recordingCoordinator: RecordingCoordinating?

    init(
        recordingCoordinator: RecordingCoordinating,
        shouldStartWatchingTriggers: Bool
    ) throws {
        self.recordingCoordinator = recordingCoordinator

        uiViewSwizzler = try UIViewSwizzler(handler: self)
        uiApplicationSwizzler = try UIApplicationSwizzler(handler: self)

        if shouldStartWatchingTriggers {
            startWatchingTriggers()
        }
    }

    deinit {
        uiViewSwizzler?.unswizzle()
        uiApplicationSwizzler?.unswizzle()
    }

    func startWatchingTriggers() {
        if recordingCoordinator?.startRecording() == true {
            uiViewSwizzler?.swizzle()
            uiApplicationSwizzler?.swizzle()
        }
    }

    func stopWatchingTriggers() {
        uiViewSwizzler?.unswizzle()
        uiApplicationSwizzler?.unswizzle()
        recordingCoordinator?.stopRecording()
    }

    func notify_layoutSubviews(view: UIView) {
        recordingCoordinator?.captureNextRecord()
    }

    func notify_sendEvent(application: UIApplication, event: UIEvent) {
        guard event.type == .touches, event.allTouches?.isEmpty == false else {
            return
        }
        recordingCoordinator?.captureNextRecord()
    }
}
