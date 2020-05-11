/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Returns `true` if the warning was raised. `false` otherwise.
internal func warn(if condition: @autoclosure () -> Bool, message: String) -> Bool {
    if condition() {
        userLogger.warn(message)
        return true
    } else {
        return false
    }
}

/// Returns `nil` if the warning was raised. `T` otherwise.
internal func warnIfCannotCast<T>(value: Any) -> T? {
    guard let castedValue = value as? T else {
        userLogger.warn("🔥 Using \(type(of: value as Any)) while \(T.self) was expected.")
        return nil
    }
    return castedValue
}
