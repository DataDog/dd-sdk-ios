/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogTrace

// swiftlint:disable identifier_name
internal extension DatadogObjc.OTTracer {
    var dd: DDTracer? { warnIfCannotCast(value: self) }
}
internal extension DatadogObjc.OTSpan {
    var dd: DDSpanObjc? { warnIfCannotCast(value: self) }
}
internal extension DatadogObjc.OTSpanContext {
    var dd: DDSpanContextObjc? { warnIfCannotCast(value: self) }
}
// swiftlint:enable identifier_name

/// Returns `nil` if the warning was raised. `T` otherwise.
private func warnIfCannotCast<T>(value: Any) -> T? {
    guard let castedValue = value as? T else {
        print("🔥 Using \(type(of: value as Any)) while \(T.self) was expected.")
        return nil
    }
    return castedValue
}
