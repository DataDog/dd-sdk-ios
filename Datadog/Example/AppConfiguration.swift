/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import Datadog

protocol AppConfiguration {
    /// Datadog SDK configuration for given app configuration.
    func sdkConfiguration() -> Datadog.Configuration

    /// Returns the initial Storyboard to launch the app in this configuration.
    func initialStoryboard() -> UIStoryboard?

    /// `TestScenario` passed in ENV parameters or `nil` if the app was launched directly.
    var testScenario: TestScenario? { get }
}

/// The configuration used when running the Example app (⌘+R).
struct ExampleAppConfiguration: AppConfiguration {
    let serviceName = "ios-sdk-example-app"
    let testScenario = Environment.testScenario()

    func sdkConfiguration() -> Datadog.Configuration {
        let configuration = Datadog.Configuration
            .builderUsing(
                rumApplicationID: Environment.readRUMApplicationID(),
                clientToken: Environment.readClientToken(),
                environment: "tests"
            )
            .set(serviceName: serviceName)

        // If the app was launched with test scenarion ENV, apply the scenario configuration
        if let testScenario = testScenario {
            testScenario.configureSDK(builder: configuration)
        }

        return configuration.build()
    }

    func initialStoryboard() -> UIStoryboard? {
        if let testScenario = testScenario {
            return UIStoryboard(name: type(of: testScenario).storyboardName, bundle: nil)
        }
        return UIStoryboard(name: "Main", bundle: nil)
    }
}

/// The configuration used when launching the Example app for Datadog SDK integration tests (⌘+U).
struct UITestsAppConfiguration: AppConfiguration {
    let testScenario = Environment.testScenario()

    func sdkConfiguration() -> Datadog.Configuration {
        deletePersistedSDKData()

        let configuration = Datadog.Configuration
            .builderUsing(
                rumApplicationID: "rum-application-id",
                clientToken: "ui-tests-client-token",
                environment: "integration"
            )
            .set(serviceName: "ui-tests-service-name")

        // If `HTTPServerMock` endpoint is set for Logging, enable the feature and send data to mock server
        if let logsEndpoint = Environment.logsEndpoint() {
            _ = configuration.set(logsEndpoint: .custom(url: logsEndpoint))
        } else {
            _ = configuration.enableLogging(false)
        }

        // If `HTTPServerMock` endpoint is set for Tracing, enable the feature and send data to mock server
        if let tracesEndpoint = Environment.tracesEndpoint() {
            _ = configuration.set(tracesEndpoint: .custom(url: tracesEndpoint))
        } else {
            _ = configuration.enableTracing(false)
        }

        // If `HTTPServerMock` endpoint is set for RUM, enable the feature and send data to mock server
        if let rumEndpoint = Environment.rumEndpoint() {
            _ = configuration.set(rumEndpoint: .custom(url: rumEndpoint))
        } else {
            _ = configuration.enableRUM(false)
        }

        // Apply the scenario configuration
        testScenario!.configureSDK(builder: configuration)

        return configuration.build()
    }

    func initialStoryboard() -> UIStoryboard? {
        return UIStoryboard(name: type(of: testScenario!).storyboardName, bundle: nil)
    }

    private func deletePersistedSDKData() {
        guard let cachesDirectoryURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }

        do {
            let dataDirectories = try FileManager.default
                .contentsOfDirectory(at: cachesDirectoryURL, includingPropertiesForKeys: [.isDirectoryKey, .canonicalPathKey])
                .filter { $0.absoluteString.contains("com.datadoghq") }

            try dataDirectories.forEach { url in
                try FileManager.default.removeItem(at: url)
                print("🧹 Deleted SDK data directory: \(url)")
            }
        } catch {
            print("🔥 Failed to delete SDK data directory: \(error)")
        }
    }
}
