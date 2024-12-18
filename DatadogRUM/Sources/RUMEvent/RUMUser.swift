/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

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
            anonymousId: nil,
            email: userInfo.email,
            id: userInfo.id,
            name: userInfo.name,
            usrInfo: userInfo.extraInfo
        )
    }
}
