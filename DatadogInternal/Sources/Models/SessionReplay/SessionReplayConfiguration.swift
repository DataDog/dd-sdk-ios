/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Available privacy levels for content masking in Session Replay.
public enum SessionReplayPrivacyLevel: String {
    /// Record all content.
    case allow

    /// Mask all content.
    case mask

    /// Mask input elements, but record all other content.
    case maskUserInput = "mask_user_input"
}

/// The Session Replay shared configuration.
///
/// The Feature object  named `session-replay` will be registered to the core
/// when enabling Session Replay. If available, the configuration can be retreived
/// with:
///
///     let sessionReplay = core.feature(
///         named: "session-replay",
///         type: SessionReplayConfiguration.self
///     )
///
public protocol SessionReplayConfiguration {
    /// The privacy level to use for the web view replay recording.
    var privacyLevel: SessionReplayPrivacyLevel { get }
}
