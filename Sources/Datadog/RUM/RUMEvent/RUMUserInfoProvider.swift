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

    var current: RUMUSR? {
        let userInfo = userInfoProvider.value

        if userInfo.id == nil && userInfo.name == nil && userInfo.email == nil {
            return nil
        } else {
            return RUMUSR(id: userInfo.id, name: userInfo.name, email: userInfo.email)
        }
    }
}
