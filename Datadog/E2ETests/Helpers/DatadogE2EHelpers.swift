/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Datadog

extension Datadog.Configuration {
    static func builderUsingE2EConfig() -> Datadog.Configuration.Builder {
        return builderUsing(
            rumApplicationID: E2EConfig.readRUMApplicationID(),
            clientToken: E2EConfig.readClientToken(),
            environment: E2EConfig.readEnv()
        ).set(sampleTelemetry: 100)
    }
}
