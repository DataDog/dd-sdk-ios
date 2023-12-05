/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import CoreGraphics

/// Sanitizes and validates Core Foundation types.
///
/// Verifies if the given `value` is of the expected type specified by `expectedTypeID`.
/// Returns the value if the type matches; otherwise, returns `nil`.
///
/// This method is used to sanitize attributes that can be set dynamically, leveraging the Objective-C runtime. For example:
///
/// ```
/// // If an invalid value is set dynamically (e.g., with User Defined Runtime Attributes in Storyboard):
/// view.setValue("string value", forKeyPath: "layer.borderColor")
///
/// // The following will crash:
/// let alpha = view.layer.borderColor?.alpha
///
/// // Sanitizing it will return `nil` and prevent the crash:
/// let alpha = sanitize(value: view.layer.borderColor, expectedTypeID: CGColor.typeID)?.alpha
/// ```
///
/// For full context, see: https://github.com/DataDog/dd-sdk-ios/pull/1373
///
/// Reference: [CFTypeRef - Core Foundation](https://developer.apple.com/documentation/corefoundation/cftyperef)
private func sanitize<T: CFTypeRef>(value: T?, expectedTypeID: CFTypeID) -> T? {
    guard let value = value, CFGetTypeID(value) == expectedTypeID else {
        return nil
    }
    return value
}

internal extension CGColor {
    /// Casts receiver to valid `CGColor` object.
    /// Returns value only if this underlying `CFTypeRef` is of `CGColor.typeID` type.
    var safeCast: CGColor? { sanitize(value: self, expectedTypeID: CGColor.typeID) }
}
#endif
