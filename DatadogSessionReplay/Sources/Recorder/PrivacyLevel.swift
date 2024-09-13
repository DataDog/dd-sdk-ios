/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import DatadogInternal

/// Text obfuscation strategies for different text types.
@_spi(Internal)
public extension TextAndInputPrivacyLevel {
    /// Returns "Sensitive Text" obfuscator for given `privacyLevel`.
    ///
    /// In Session Replay, "Sensitive Text" is:
    /// - passwords, e-mails and phone numbers marked in a platform-specific way
    /// - AND other forms of sensitivity in text available to each platform
    var sensitiveTextObfuscator: SessionReplayTextObfuscating {
        return FixLengthMaskObfuscator()
    }

    /// Returns "Input & Option Text" obfuscator for given `TextAndInputPrivacyLevel`.
    ///
    /// In Session Replay, "Input & Option Text" is:
    /// - a text entered by the user with a keyboard or other text-input device (eg. `UITextField`)
    /// - OR a custom (non-generic) value in selection elements (eg. `UISwitch`)
    var inputAndOptionTextObfuscator: SessionReplayTextObfuscating {
        switch self {
        case .maskSensitiveInputs:  return NOPTextObfuscator()
        case .maskAllInputs:        return FixLengthMaskObfuscator()
        case .maskAll:              return FixLengthMaskObfuscator()
        }
    }

    /// Returns "Static Text" obfuscator for given `TextAndInputPrivacyLevel`.
    ///
    /// In Session Replay, "Static Text" is a text not directly entered by the user (eg. `UILabel`)
    var staticTextObfuscator: SessionReplayTextObfuscating {
        switch self {
        case .maskSensitiveInputs:  return NOPTextObfuscator()
        case .maskAllInputs:        return NOPTextObfuscator()
        case .maskAll:              return SpacePreservingMaskObfuscator()
        }
    }

    /// Returns "Hint Text" obfuscator for given `TextAndInputPrivacyLevel`.
    ///
    /// In Session Replay, "Hint Text" is a static text in editable text elements or option selectors, displayed when there isn't any value set. (eg. `UITextField.placeholder`)
    var hintTextObfuscator: SessionReplayTextObfuscating {
        switch self {
        case .maskSensitiveInputs:  return NOPTextObfuscator()
        case .maskAllInputs:        return NOPTextObfuscator()
        case .maskAll:              return FixLengthMaskObfuscator()
        }
    }
}

/// Other convenience helpers.
internal extension TextAndInputPrivacyLevel {
    /// If input elements should be masked in this privacy mode.
    var shouldMaskInputElements: Bool {
        switch self {
        case .maskAll, .maskAllInputs: return true
        case .maskSensitiveInputs: return false
        }
    }
}
#endif
