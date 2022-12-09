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

/// Text obfuscator which replaces all readable characters with `"x"`.
internal struct TextObfuscator: TextObfuscating {
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

/// Text obfuscator which only returns the original text.
internal struct NOPTextObfuscator: TextObfuscating {
    func mask(text: String) -> String {
        return text
    }
}

/// Text obfuscator which only returns the original text.
internal let nopTextObfuscator: TextObfuscating = NOPTextObfuscator()
