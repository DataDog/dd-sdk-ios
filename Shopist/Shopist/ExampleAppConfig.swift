/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Basic configuration to read your Datadog client token from `examples-secret.xcconfig`.
struct ExampleAppConfig {
    let clientToken: String

    init() {
        guard let clientToken = Bundle.main.infoDictionary?["DatadogClientToken"] as? String, !clientToken.isEmpty else {
            // If you see this error when running example app it means your `examples-secret.xcconfig` file is
            // missing or missconfigured. Please refer to `README.md` file in SDK's repository root folder
            // to create it.
            fatalError("""
            ✋⛔️ Cannot read `DATADOG_CLIENT_TOKEN` from `Info.plist` dictionary.
            Please create `shopist-secrets.local.xcconfig` in the same folder with `Shopist.xcconfig`
            and declare your `DATADOG_CLIENT_TOKEN="your-client-token"`
            You might need to run `Product > Clean Build Folder` before retrying.
            """)
        }

        self.clientToken = clientToken
    }
}
