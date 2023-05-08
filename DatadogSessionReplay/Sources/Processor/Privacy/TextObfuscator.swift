/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal protocol TextObfuscating {
    /// Obfuscates given `text`.
    /// - Parameter text: the text to be obfuscated
    /// - Returns: obfuscated text
    func mask(text: String) -> String
}

/// Text obfuscation strategies for different text types.
internal struct TextObfuscation {
    /// Text obfuscator that returns original text (no obfuscation).
    private let nop = NOPTextObfuscator()
    /// Text obfuscator that replaces each character with `"x"` mask.
    private let spacePreservingMask = SpacePreservingMaskObfuscator()
    /// Text obfuscator that replaces whole text with fixed-length `"***"` mask (three asterics).
    private let fixLegthMask = FixLegthMaskObfuscator()

    /// Returns "Sensitive Text" obfuscator for given `privacyLevel`.
    ///
    /// In Session Replay, "Sensitive Text" is:
    /// - passwords, e-mails and phone numbers marked in a platform-specific way
    /// - AND other forms of sensitivity in text available to each platform
    func sensitiveTextObfuscator(for privacyLevel: SessionReplayPrivacy) -> TextObfuscating {
        return fixLegthMask
    }

    /// Returns "Input & Option Text" obfuscator for given `privacyLevel`.
    ///
    /// In Session Replay, "Input & Option Text" is:
    /// - a text entered by the user with a keyboard or other text-input device
    /// - OR a custom (non-generic) value in selection elements
    func inputAndOptionTextObfuscator(for privacyLevel: SessionReplayPrivacy) -> TextObfuscating {
        switch privacyLevel {
        case .allowAll:         return nop
        case .maskAll:          return fixLegthMask
        case .maskUserInput:    return fixLegthMask
        }
    }

    /// Returns "Static Text" obfuscator for given `privacyLevel`.
    ///
    /// In Session Replay, "Static Text" is a text not directly entered by the user.
    func staticTextObfuscator(for privacyLevel: SessionReplayPrivacy) -> TextObfuscating {
        switch privacyLevel {
        case .allowAll:         return nop
        case .maskAll:          return spacePreservingMask
        case .maskUserInput:    return nop
        }
    }

    /// Returns "Hint Text" obfuscator for given `privacyLevel`.
    ///
    /// In Session Replay, "Hint Text" is a static text in editable text elements or option selectors, displayed when there isn't any value set.
    func hintTextObfuscator(for privacyLevel: SessionReplayPrivacy) -> TextObfuscating {
        switch privacyLevel {
        case .allowAll:         return nop
        case .maskAll:          return fixLegthMask
        case .maskUserInput:    return nop
        }
    }
}

/// Text obfuscator which replaces all readable characters with space-preserving `"x"` characters.
internal struct SpacePreservingMaskObfuscator: TextObfuscating {
    /// The character to mask text with.
    let maskCharacter: UnicodeScalar = "x"

    /// Masks given `text` by replacing all not whitespace characters with `"x"`.
    /// - Parameter text: the text to be masked
    /// - Returns: masked text
    func mask(text: String) -> String {
        var masked = ""

        var iterator = text.unicodeScalars.makeIterator()

        while let nextScalar = iterator.next() {
            switch nextScalar {
            case " ", "\n", "\r", "\t":
                masked.unicodeScalars.append(nextScalar)
            default:
                masked.unicodeScalars.append(maskCharacter)
            }
        }

        return masked
    }
}

/// Text obfuscator which replaces entire text with fix-length `"***"` mask value.
internal struct FixLegthMaskObfuscator: TextObfuscating {
    private static let maskedString = "***"

    func mask(text: String) -> String { Self.maskedString }
}

/// Text obfuscator which returns the original text.
internal struct NOPTextObfuscator: TextObfuscating {
    func mask(text: String) -> String {
        return text
    }
}
