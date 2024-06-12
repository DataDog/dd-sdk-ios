/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal extension UITraitEnvironment {
    var usesDarkMode: Bool {
        return traitCollection.userInterfaceStyle == .dark
    }
}

/// Sensitive text content types as defined in Session Replay.
internal let sensitiveContentTypes: Set<UITextContentType> = {
    return [
        .password,
        .emailAddress,
        .telephoneNumber,
        .addressCity, .addressState, .addressCityAndState, .fullStreetAddress, .streetAddressLine1, .streetAddressLine2, .postalCode,
        .creditCardNumber,
        .newPassword,
        .oneTimeCode,
    ]
}()

internal extension UITextInputTraits {
    /// Whether or not these input traits describe a "Sensitive Text".
    ///
    /// In Session Replay, "Sensitive Text" is:
    /// - passwords, e-mails and phone numbers marked in a platform-specific way
    /// - AND other forms of sensitivity in text available to each platform
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
#endif
