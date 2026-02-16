/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Shared control surface for Session Replay recording coordinators.
//
// This protocol keeps `SessionReplayFeature` independent from the concrete recording
// strategy (view-tree or layer-tree) while exposing common lifecycle and privacy/sampling
// state used in feature orchestration.

#if os(iOS)
import Foundation
import DatadogInternal

internal protocol RecordingController: AnyObject {
    var sampler: Sampler { get }
    var textAndInputPrivacy: TextAndInputPrivacyLevel { get }
    var imagePrivacy: ImagePrivacyLevel { get }
    var touchPrivacy: TouchPrivacyLevel { get }

    func startRecording()
    func stopRecording()
}

extension RecordingCoordinator: RecordingController {
}
#endif
