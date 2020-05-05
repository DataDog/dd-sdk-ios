/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

struct ExampleAppConfig {
    /// Client token read from `shopist-secrets.local.xcconfig`.
    let clientToken: String
    /// Service name used for logs and traces.
    let serviceName: String

    init(serviceName: String) {
        guard let clientToken = Bundle.main.infoDictionary?["DatadogClientToken"] as? String, !clientToken.isEmpty else {
            fatalError("""
            ✋⛔️ Cannot read `DATADOG_CLIENT_TOKEN` from `Info.plist` dictionary.
            Please create `shopist-secrets.local.xcconfig` in the same folder with `Shopist.xcconfig`
            and declare your `DATADOG_CLIENT_TOKEN="your-client-token"`
            You might need to run `Product > Clean Build Folder` before retrying.
            """)
        }

        self.clientToken = clientToken
        self.serviceName = serviceName
    }
}
