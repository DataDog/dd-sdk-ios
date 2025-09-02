/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit
import DatadogInternal

#if $RetroactiveAttribute
extension UIView: @retroactive DatadogExtended { }
#else
extension UIView: DatadogExtended { }
#endif

/// Sensitive text content types as defined in Session Replay.
private let UITextContentSensitiveTypes: Set<UITextContentType> = [
    .password,
    .emailAddress,
    .telephoneNumber,
    .addressCity, .addressState, .addressCityAndState, .fullStreetAddress, .streetAddressLine1, .streetAddressLine2, .postalCode,
    .creditCardNumber,
    .newPassword,
    .oneTimeCode,
]

private var UITextInputTraitsIsSensitiveTextKey: UInt8 = 0

internal extension DatadogExtension where ExtendedType: UITextInputTraits {
    /// Sensitive text content types as defined in Session Replay.
    static var sensitiveTypes: Set<UITextContentType> {
        UITextContentSensitiveTypes
    }

    /// Whether or not these input traits describe a "Sensitive Text".
    ///
    /// The input traits will still be considered sensitive if its sensitivity or its
    /// content type change.
    ///
    /// In Session Replay, "Sensitive Text" is:
    /// - passwords, e-mails and phone numbers marked in a platform-specific way
    /// - AND other forms of sensitivity in text available to each platform
    var isSensitiveText: Bool {
        if objc_getAssociatedObject(type, &UITextInputTraitsIsSensitiveTextKey) as? Bool == true {
            return true
        }

        if type.isSecureTextEntry == true {
            objc_setAssociatedObject(type, &UITextInputTraitsIsSensitiveTextKey, true, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return true
        }

        let isSensitiveContentType = type.textContentType.map {
            UITextContentSensitiveTypes.contains($0)
        }

        if isSensitiveContentType == true {
            objc_setAssociatedObject(type, &UITextInputTraitsIsSensitiveTextKey, true, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return true
        }

        return false
    }
}

internal extension DatadogExtension where ExtendedType: UITraitEnvironment {
    var usesDarkMode: Bool { type.traitCollection.userInterfaceStyle == .dark }
}

#endif
