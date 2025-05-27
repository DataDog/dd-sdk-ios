/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public let SessionReplayFeatureName = "session-replay"

// MARK: Deprecated Global Privacy Level

/// Available privacy levels for content masking in Session Replay.
public enum SessionReplayPrivacyLevel: String {
    /// Record all content.
    case allow

    /// Mask all content.
    case mask

    /// Mask input elements, but record all other content.
    case maskUserInput = "mask-user-input"
}

// MARK: Fine-Grained Privacy Levels

/// Available privacy levels for text and input masking in Session Replay.
public enum TextAndInputPrivacyLevel: String, CaseIterable {
    /// Show all texts except sensitive inputs, eg. password fields.
    case maskSensitiveInputs = "mask_sensitive_inputs"

    /// Mask all inputs fields, eg. textfields, switches, checkboxes.
    case maskAllInputs = "mask_all_inputs"

    /// Mask all texts and inputs, eg. labels.
    case maskAll = "mask_all"
}

/// Available privacy levels for image masking in the Session Replay.
public enum ImagePrivacyLevel: String {
    /// Only SF Symbols and images loaded using UIImage(named:) that are bundled within the application will be recorded.
    case maskNonBundledOnly = "mask_non_bundled_only"

    /// No images will be recorded.
    case maskAll = "mask_all"

    /// All images will be recorded, including the ones downloaded from the Internet or generated during the app runtime.
    case maskNone = "mask_none"
}

/// Available privacy levels for touch masking in Session Replay.
public enum TouchPrivacyLevel: String {
    /// Show all user touches.
    case show

    /// Hide all user touches.
    case hide
}

// MARK: SessionReplayConfiguration

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
    /// Fine-Grained privacy levels to use in Session Replay.
    var textAndInputPrivacyLevel: TextAndInputPrivacyLevel { get }
    var imagePrivacyLevel: ImagePrivacyLevel { get }
    var touchPrivacyLevel: TouchPrivacyLevel { get }
}

extension DatadogFeature where Self: SessionReplayConfiguration {
    public static var name: String { SessionReplayFeatureName }
}
