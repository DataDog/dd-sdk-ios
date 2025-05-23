/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension RUMAccount {
    init?(context: DatadogContext) {
        guard let accountInfo = context.accountInfo else {
            return nil
        }

        self.init(accountInfo: accountInfo)
    }

    init(accountInfo: AccountInfo) {
        self.init(
            id: accountInfo.id,
            name: accountInfo.name,
            accountInfo: accountInfo.extraInfo
        )
    }
}
