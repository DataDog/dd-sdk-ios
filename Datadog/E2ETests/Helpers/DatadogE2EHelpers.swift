/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Datadog

extension DatadogSDK.Configuration {
    static func builderUsingE2EConfig() -> DatadogSDK.Configuration.Builder {
        return builderUsing(
            rumApplicationID: E2EConfig.readRUMApplicationID(),
            clientToken: E2EConfig.readClientToken(),
            environment: E2EConfig.readEnv()
        )
    }
}
