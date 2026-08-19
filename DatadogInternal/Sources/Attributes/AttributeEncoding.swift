/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Context for attribute encoding, used to provide clearer error messages to customers.
public enum AttributeEncodingContext {
    /// User-provided custom attribute
    case custom
    /// User info extra attribute (usr.*)
    case userInfo
    /// Account info extra attribute (account.*)
    case accountInfo
    /// Internal SDK attribute
    case `internal`

    public var errorMessagePrefix: String {
        switch self {
        case .custom:
            return ""
        case .userInfo:
            return "user info "
        case .accountInfo:
            return "account "
        case .internal:
            return "internal "
        }
    }
}
