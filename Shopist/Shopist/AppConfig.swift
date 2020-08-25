/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct AppConfig {
    /// Client token read from `Datadog.xcconfig`.
    let clientToken: String
    /// Service name used for logs and traces.
    let serviceName: String
    /// RUM application identifier
    let rumAppID: String
    /// Client token read from `Datadog.xcconfig`.
    let rumClientToken: String

    init(serviceName: String) {
        guard let rumClientToken = Bundle.main.infoDictionary?["DatadogClientToken"] as? String, !rumClientToken.isEmpty else {
            fatalError("""
            ✋⛔️ Cannot read `DATADOG_CLIENT_TOKEN` from `Info.plist` dictionary.
            Please update `Datadog.xcconfig` in the repository root with your own
            client token obtained on datadoghq.com.
            You might need to run `Product > Clean Build Folder` before retrying.
            """
            )
        }
        guard let rumAppID = Bundle.main.infoDictionary?["RUMAppID"] as? String, !rumAppID.isEmpty else {
            fatalError(
                """
            ✋⛔️ Cannot read `RUM_APP_ID` from `Info.plist` dictionary.
            Please update `Shopist.xcconfig` in the repository root with your own
            RUM application identifier obtained on datadoghq.com.
            You might need to run `Product > Clean Build Folder` before retrying.
            """
            )
        }

        self.rumClientToken = rumClientToken
        self.serviceName = serviceName
        self.rumAppID = rumAppID
    }
}
