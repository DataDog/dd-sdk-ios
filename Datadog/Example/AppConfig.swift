/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Datadog

protocol AppConfig {
    /// Example app's service name.
    var serviceName: String { get }
    /// RUM application id.
    var rumApplicationID: String { get }
    /// SDK configuration
    var datadogConfiguration: Datadog.Configuration { get }
    /// Endpoints for arbitrary network requests
    var arbitraryNetworkURL: URL { get }
    var arbitraryNetworkRequest: URLRequest { get }
}

struct ExampleAppConfig: AppConfig {
    /// Service name used for logs and traces.
    let serviceName = "ios-sdk-example-app"
    /// RUM application ID obtained on datadohq.com
    let rumApplicationID: String
    /// Configuration for uploading logs to Datadog servers
    let datadogConfiguration: Datadog.Configuration

    let arbitraryNetworkURL = URL(string: "https://status.datadoghq.com")!
    let arbitraryNetworkRequest: URLRequest = {
        var request = URLRequest(url: URL(string: "https://status.datadoghq.com/bad/path")!)
        request.httpMethod = "POST"
        request.addValue("dataTaskWithRequest", forHTTPHeaderField: "creation-method")
        return request
    }()

    init() {
        guard let clientToken = Bundle.main.infoDictionary?["DatadogClientToken"] as? String, !clientToken.isEmpty else {
            fatalError("""
            ✋⛔️ Cannot read `DATADOG_CLIENT_TOKEN` from `Info.plist` dictionary.
            Please update `Datadog.xcconfig` in the repository root with your own
            client token obtained on datadoghq.com.
            You might need to run `Product > Clean Build Folder` before retrying.
            """)
        }

        guard let rumApplicationID = Bundle.main.infoDictionary!["RUMApplicationID"] as? String, !clientToken.isEmpty else {
            fatalError("""
            ✋⛔️ Cannot read `RUM_APPLICATION_ID` from `Info.plist` dictionary.
            Please update `Datadog.xcconfig` in the repository root with your own
            RUM application id obtained on datadoghq.com.
            You might need to run `Product > Clean Build Folder` before retrying.
            """)
        }

        self.rumApplicationID = rumApplicationID
        self.datadogConfiguration = Datadog.Configuration
            .builderUsing(clientToken: clientToken, environment: "tests")
            .set(serviceName: serviceName)
            .set(tracedHosts: [arbitraryNetworkURL.host!, "foo.bar"])
            .build()
    }
}

struct UITestAppConfig: AppConfig {
    /// Mocked service name for UITests
    let serviceName = "ui-tests-service-name"
    /// Mocked RUM application ID
    let rumApplicationID: String = "rum-application-id"
    /// Configuration for uploading logs to mock servers
    let datadogConfiguration: Datadog.Configuration
    let arbitraryNetworkURL: URL
    let arbitraryNetworkRequest: URLRequest

    init() {
        let mockLogsEndpoint = ProcessInfo.processInfo.environment["DD_MOCK_LOGS_ENDPOINT_URL"]!
        let mockTracesEndpoint = ProcessInfo.processInfo.environment["DD_MOCK_TRACES_ENDPOINT_URL"]!
        let sourceEndpoint = ProcessInfo.processInfo.environment["DD_MOCK_SOURCE_ENDPOINT_URL"]!
        let tracedhost = URL(string: sourceEndpoint)!.host!
        self.datadogConfiguration = Datadog.Configuration
            .builderUsing(clientToken: "ui-tests-client-token", environment: "integration")
            .set(serviceName: serviceName)
            .set(logsEndpoint: .custom(url: mockLogsEndpoint))
            .set(tracesEndpoint: .custom(url: mockTracesEndpoint))
            .set(tracedHosts: [tracedhost, "foo.bar"])
            .build()

        let url = URL(string: sourceEndpoint)!
        self.arbitraryNetworkURL = URL(string: url.deletingLastPathComponent().absoluteString + "inspect")!
        self.arbitraryNetworkRequest = {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("dataTaskWithRequest", forHTTPHeaderField: "creation-method")
            return request
        }()
    }
}

/// Returns different `AppConfig` when running in UI Tests or launching directly.
func currentAppConfig() -> AppConfig {
    if ProcessInfo.processInfo.arguments.contains("IS_RUNNING_UI_TESTS") {
        return UITestAppConfig()
    } else {
        return ExampleAppConfig()
    }
}
