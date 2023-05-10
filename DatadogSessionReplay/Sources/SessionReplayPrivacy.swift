/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

/// Session Replay content recording policy.
/// It describes the way in which sensitive content (e.g. text or images) should be captured.
public enum SessionReplayPrivacy {
    /// Record all content as it is.
    /// When using this option: all text, images and other information will be recorded and presented in the player.
    case allowAll

    /// Mask all content.
    /// When using this option: all characters in texts will be replaced with "x", images will be
    /// replaced with placeholders and other content will be masked accordingly, so the original
    /// information will not be presented in the player.
    ///
    /// This is the default content policy.
    case maskAll

    /// Mask input elements, but record all other content as it is.
    /// When uing this option: all user input and selected values (text fields, switches, pickers, segmented controls etc.) will be masked,
    /// but static text (e.g. in labels) will be not.
    case maskUserInput
}

/// Text obfuscation strategies for different text types.
internal extension SessionReplayPrivacy {
    /// Returns "Sensitive Text" obfuscator for given `privacyLevel`.
    ///
    /// In Session Replay, "Sensitive Text" is:
    /// - passwords, e-mails and phone numbers marked in a platform-specific way
    /// - AND other forms of sensitivity in text available to each platform
    var sensitiveTextObfuscator: TextObfuscating {
        return FixLengthMaskObfuscator()
    }

    /// Returns "Input & Option Text" obfuscator for given `privacyLevel`.
    ///
    /// In Session Replay, "Input & Option Text" is:
    /// - a text entered by the user with a keyboard or other text-input device
    /// - OR a custom (non-generic) value in selection elements
    var inputAndOptionTextObfuscator: TextObfuscating {
        switch self {
        case .allowAll:         return NOPTextObfuscator()
        case .maskAll:          return FixLengthMaskObfuscator()
        case .maskUserInput:    return FixLengthMaskObfuscator()
        }
    }

    /// Returns "Static Text" obfuscator for given `privacyLevel`.
    ///
    /// In Session Replay, "Static Text" is a text not directly entered by the user.
    var staticTextObfuscator: TextObfuscating {
        switch self {
        case .allowAll:         return NOPTextObfuscator()
        case .maskAll:          return SpacePreservingMaskObfuscator()
        case .maskUserInput:    return NOPTextObfuscator()
        }
    }

    /// Returns "Hint Text" obfuscator for given `privacyLevel`.
    ///
    /// In Session Replay, "Hint Text" is a static text in editable text elements or option selectors, displayed when there isn't any value set.
    var hintTextObfuscator: TextObfuscating {
        switch self {
        case .allowAll:         return NOPTextObfuscator()
        case .maskAll:          return FixLengthMaskObfuscator()
        case .maskUserInput:    return NOPTextObfuscator()
        }
    }
}

/// Other convenience helpers.
internal extension SessionReplayPrivacy {
    /// If input elements should be masked in this privacy mode.
    var shouldMaskInputElements: Bool {
        switch self {
        case .maskAll, .maskUserInput: return true
        case .allowAll: return false
        }
    }
}
