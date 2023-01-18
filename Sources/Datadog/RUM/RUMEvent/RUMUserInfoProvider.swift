/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Maps the value from shared `UserInfoProvider` to `RUMUSR` format.
internal struct RUMUserInfoProvider {
    /// Shared user info provider.
    let userInfoProvider: UserInfoProvider

    var current: RUMUser? {
        let userInfo = userInfoProvider.value

        // Returns nil if UserInfo has no data
        if userInfo.id == nil, userInfo.name == nil, userInfo.email == nil, userInfo.extraInfo.isEmpty {
            return nil
        }

        return RUMUser(userInfo: userInfo)
    }
}

extension RUMUser {
    init?(context: DatadogContext) {
        guard let userInfo = context.userInfo else {
            return nil
        }

        if userInfo.id == nil, userInfo.name == nil, userInfo.email == nil, userInfo.extraInfo.isEmpty {
            return nil
        }

        self.init(userInfo: userInfo)
    }

    init(userInfo: UserInfo) {
        self.init(
            email: userInfo.email,
            id: userInfo.id,
            name: userInfo.name,
            usrInfo: userInfo.extraInfo
        )
    }
}
