/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

protocol AppConfig {
    /// Client token obtained on Datadog website.
    var clientToken: String { get }
    /// Service name used for logs and traces.
    var serviceName: String { get }
}

struct ExampleAppConfig: AppConfig {
    /// Client token read from `datadog.local.xcconfig`.
    let clientToken: String
    /// Service name used for logs and traces.
    let serviceName = "ios-sdk-example-app"

    init() {
        guard let clientToken = Bundle.main.infoDictionary?["DatadogClientToken"] as? String, !clientToken.isEmpty else {
            fatalError("""
            ✋⛔️ Cannot read `DATADOG_CLIENT_TOKEN` from `Info.plist` dictionary.
            Please update `Datadog.xcconfig` in the repository root with your own
            client token obtained on datadoghq.com.
            You might need to run `Product > Clean Build Folder` before retrying.
            """)
        }

        self.clientToken = clientToken
    }
}

struct UITestAppConfig: AppConfig {
    /// Mocked client token for UITests
    let clientToken = "uitests-client-token"
    /// Mocked service name for UITests
    let serviceName = "uitests-service-name"
}

/// Returns different `AppConfig` when running in UI Tests or launching directly.
func currentAppConfig() -> AppConfig {
    if ProcessInfo.processInfo.arguments.contains("IS_RUNNING_UI_TESTS") {
        return UITestAppConfig()
    } else {
        return ExampleAppConfig()
    }
}
