/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public let SessionReplayFeaturneName = "session-replay"

/// Available privacy levels for content masking in Session Replay.
public enum SessionReplayPrivacyLevel: String {
    /// Record all content.
    case allow

    /// Mask all content.
    case mask

    /// Mask input elements, but record all other content.
    case maskUserInput = "mask_user_input"
}

/// Available privacy levels for text and input masking in Session Replay.
public enum SessionReplayTextAndInputPrivacyLevel: String {
    /// Show all texts except sensitive inputs, eg. password fields.
    case maskSensitiveInputs = "mask_sensitive_inputs"

    /// Mask all inputs fields, eg. textfields, switches, checkboxes.
    case maskAllInputs = "mask_all_inputs"

    /// Mask all texts and inputs, eg. labels.
    case maskAll = "mask_all"
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
    /// The text and input privacy level to use for the web view replay recording.
    var textAndInputPrivacyLevel: SessionReplayTextAndInputPrivacyLevel { get }
}

extension DatadogFeature where Self: SessionReplayConfiguration {
    public static var name: String { SessionReplayFeaturneName }
}
