/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Maps the value from shared `UserInfoProvider` to `RUMUSR` format.
internal struct RUMUserInfoProvider {
    /// Shared user info provider.
    let userInfoProvider: UserInfoProvider

    var current: RUMUser? {
        let user = userInfoProvider.value

        // Returns nil if UserInfo has no data
        if user.id == nil, user.name == nil, user.email == nil, user.extraInfo.isEmpty {
            return nil
        }

        return RUMUser(
            email: user.email,
            id: user.id,
            name: user.name,
            usrInfo: user.extraInfo
        )
    }
}
