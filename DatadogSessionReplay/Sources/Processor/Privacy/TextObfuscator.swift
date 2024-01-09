/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

@_spi(Internal)
public protocol SessionReplayTextObfuscating {
    /// Obfuscates given `text`.
    /// - Parameter text: the text to be obfuscated
    /// - Returns: obfuscated text
    func mask(text: String) -> String
}

internal typealias TextObfuscating = SessionReplayTextObfuscating

/// Text obfuscator which replaces all readable characters with space-preserving `"x"` characters.
internal struct SpacePreservingMaskObfuscator: TextObfuscating {
    /// The character to mask text with.
    private static let maskCharacter: UnicodeScalar = "x"

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
                masked.unicodeScalars.append(SpacePreservingMaskObfuscator.maskCharacter)
            }
        }

        return masked
    }
}

/// Text obfuscator which replaces entire text with fix-length `"***"` mask value.
internal struct FixLengthMaskObfuscator: TextObfuscating {
    private static let maskedString = "***"

    func mask(text: String) -> String { Self.maskedString }
}

/// Text obfuscator which returns the original text.
internal struct NOPTextObfuscator: TextObfuscating {
    func mask(text: String) -> String {
        return text
    }
}
#endif
