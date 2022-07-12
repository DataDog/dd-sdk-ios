/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct UserInfo {
    /// User ID, if any.
    internal let id: String?
    /// Name representing the user, if any.
    internal let name: String?
    /// User email, if any.
    internal let email: String?
    /// User custom attributes, if any.
    internal var extraInfo: [AttributeKey: AttributeValue]
}

extension UserInfo {
    internal static var empty: Self {
        .init(
            id: nil,
            name: nil,
            email: nil,
            extraInfo: [:]
        )
    }
}
