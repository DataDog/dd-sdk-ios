/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Datadog_tvOS

struct tvOSAppConfig {
    /// Service name used for logs and traces.
    let serviceName = "ios-sdk-example-tvOS-app"
    /// Configuration for uploading logs to Datadog servers
    let datadogConfiguration: Datadog.Configuration

    init() {
        guard let clientToken = Bundle.main.infoDictionary?["DatadogClientToken"] as? String, !clientToken.isEmpty else {
            fatalError("""
            ✋⛔️ Cannot read `DATADOG_CLIENT_TOKEN` from `Info.plist` dictionary.
            Please update `Datadog.xcconfig` in the repository root with your own
            client token obtained on datadoghq.com.
            You might need to run `Product > Clean Build Folder` before retrying.
            """)
        }

        guard let rumApplicationID = Bundle.main.infoDictionary!["RUMApplicationID"] as? String, !rumApplicationID.isEmpty else {
            fatalError("""
            ✋⛔️ Cannot read `RUM_APPLICATION_ID` from `Info.plist` dictionary.
            Please update `Datadog.xcconfig` in the repository root with your own
            RUM application id obtained on datadoghq.com.
            You might need to run `Product > Clean Build Folder` before retrying.
            """)
        }

        self.datadogConfiguration = Datadog.Configuration
            .builderUsing(
                rumApplicationID: rumApplicationID,
                clientToken: clientToken,
                environment: "tests"
            )
            .set(serviceName: serviceName)
            .build()
    }
}
