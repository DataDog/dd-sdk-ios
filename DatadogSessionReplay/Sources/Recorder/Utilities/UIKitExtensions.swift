/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal extension UIView {
    var usesDarkMode: Bool {
        if #available(iOS 12.0, *) {
            return traitCollection.userInterfaceStyle == .dark
        } else {
            return false // assume "no"
        }
    }
}

/// Sensitive text content types as defined in Session Replay.
internal let sensitiveContentTypes: Set<UITextContentType> = {
    var all: Set<UITextContentType> = [
        .password,
        .emailAddress,
        .telephoneNumber,
        .addressCity, .addressState, .addressCityAndState, .fullStreetAddress, .streetAddressLine1, .streetAddressLine2, .postalCode,
        .creditCardNumber
    ]

    if #available(iOS 12.0, *) {
        all.formUnion([.newPassword, .oneTimeCode])
    }

    return all
}()

internal extension UITextInputTraits {
    /// Whether or not these input traits describe a "sensitive text" as we define it in Session Replay.
    ///
    /// Sensitive texts include:
    /// - passwords, e-mails, phone numbers, address information, credit card numbers and one-time codes;
    /// - all texts marked explicitly as secure entry.
    var isSensitiveText: Bool {
        if isSecureTextEntry == true {
            return true
        }

        if let contentType = textContentType, let contentType = contentType {
            return sensitiveContentTypes.contains(contentType)
        }

        return false
    }
}
