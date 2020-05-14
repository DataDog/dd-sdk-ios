/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Datadog

protocol AppConfig {
    /// Service name used for logs and traces.
    var serviceName: String { get }
    /// SDK configuration
    var datadogConfiguration: Datadog.Configuration { get }
}

struct ExampleAppConfig: AppConfig {
    /// Service name used for logs and traces.
    let serviceName = "ios-sdk-example-app"
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

        self.datadogConfiguration = Datadog.Configuration
            .builderUsing(clientToken: clientToken, environment: "tests")
            .build()
    }
}

struct UITestAppConfig: AppConfig {
    /// Mocked service name for UITests
    let serviceName = "ui-tests-service-name"
    /// Configuration for uploading logs to mock servers
    let datadogConfiguration: Datadog.Configuration

    init(mockServerURL: String) {
        self.datadogConfiguration = Datadog.Configuration
            .builderUsing(clientToken: "ui-tests-client-token", environment: "integration")
            .set(logsEndpoint: .custom(url: mockServerURL))
            .set(tracesEndpoint: .custom(url: mockServerURL))
            .build()
    }
}

/// Returns different `AppConfig` when running in UI Tests or launching directly.
func currentAppConfig() -> AppConfig {
    if ProcessInfo.processInfo.arguments.contains("IS_RUNNING_UI_TESTS") {
        return UITestAppConfig(
            mockServerURL: ProcessInfo.processInfo.environment["DD_MOCK_SERVER_URL"]!
        )
    } else {
        return ExampleAppConfig()
    }
}
