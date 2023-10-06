/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal enum MetaTypeExtensions {
    static func key(from anyClass: Any) -> String {
        let fullName = String(reflecting: anyClass)

        // fullName may have infix like "(unknown context at $1130f7094)", remove everything inside parenthesis including parenthesis
        // Read more: https://github.com/apple/swift/issues/49336
        var key = ""
        var parenthesisCount = 0
        for char in fullName {
            if char == "(" {
                parenthesisCount += 1
            } else if char == ")" {
                parenthesisCount -= 1
            } else if parenthesisCount == 0 {
                key.append(char)
            }
        }

        // replace multiple consecutive . with single .
        var sanitizedKey = ""
        for char in key {
            if sanitizedKey.last == "." && char == "." {
                continue
            }
            sanitizedKey.append(char)
        }

        return sanitizedKey
    }
}
