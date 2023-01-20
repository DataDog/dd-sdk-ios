/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/* public */ internal struct DynamicCodingKey: CodingKey, Hashable {
    /// The string to use in a named collection (e.g. a string-keyed dictionary).
    /* public */ var stringValue: String

    /// Creates a new instance from the given string.
    ///
    /// If the string passed as `stringValue` does not correspond to any instance
    /// of this type, the result is `nil`.
    ///
    /// - parameter stringValue: The string value of the desired key.
    /* public */ init?(stringValue: String) {
        self.stringValue = stringValue
    }

    /// The value to use in an integer-indexed collection (e.g. an int-keyed
    /// dictionary).
    /* public */ var intValue: Int?

    /// Creates a new instance from the specified integer.
    ///
    /// If the value passed as `intValue` does not correspond to any instance of
    /// this type, the result is `nil`.
    ///
    /// - parameter intValue: The integer value of the desired key.
    /* public */ init?(intValue: Int) {
        return nil
    }

    /// Creates a new instance from the given string.
    ///
    /// - parameter stringValue: The string value of the desired key.
    /* public */ init(_ stringValue: String) {
        self.stringValue = stringValue
    }
}

extension DynamicCodingKey: ExpressibleByStringLiteral {
    /// Creates an instance initialized to the given string value.
    ///
    /// - Parameter value: The value of the new instance.
    init(stringLiteral value: String) {
        self.init(value)
    }
}
