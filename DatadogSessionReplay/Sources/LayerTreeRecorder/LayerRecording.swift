/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Defines the recording contract and immutable context passed to layer recorders.
//
// `LayerRecordingContext` mirrors the view/session/telemetry metadata needed to
// build replay records for a capture cycle. The protocol isolates scheduling from
// orchestration so coordinators can remain agnostic of recorder implementation.

#if os(iOS)
import Foundation
@preconcurrency import DatadogInternal

@available(iOS 13.0, tvOS 13.0, *)
internal struct LayerRecordingContext: Sendable {
    let textAndInputPrivacy: TextAndInputPrivacyLevel
    let imagePrivacy: ImagePrivacyLevel
    let touchPrivacy: TouchPrivacyLevel
    let applicationID: String
    let sessionID: String
    let viewID: String
    let viewServerTimeOffset: TimeInterval?
    let date: Date
    let telemetry: any Telemetry
}

@available(iOS 13.0, tvOS 13.0, *)
internal protocol LayerRecording {
    func scheduleRecording(_ changes: CALayerChangeset, context: LayerRecordingContext) async
}
#endif
