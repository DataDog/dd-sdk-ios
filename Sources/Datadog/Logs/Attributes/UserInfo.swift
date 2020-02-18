/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Shared user info provider.
internal class UserInfoProvider {
    var value = UserInfo(id: nil, name: nil, email: nil)
}

/// Information about the user.
internal struct UserInfo {
    let id: String? // swiftlint:disable:this identifier_name
    let name: String?
    let email: String?
}
