/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import Datadog
import DatadogCrashReporting

protocol AppConfiguration {
    /// The tracking consent value applied when initializing the SDK.
    var initialTrackingConsent: TrackingConsent { get }

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
    let testScenario: TestScenario? = Environment.testScenarioClassName()
        .flatMap { className in initializeTestScenario(with: className) }

    let initialTrackingConsent: TrackingConsent = .granted

    func sdkConfiguration() -> Datadog.Configuration {
        let configuration = Datadog.Configuration
            .builderUsing(
                rumApplicationID: Environment.readRUMApplicationID(),
                clientToken: Environment.readClientToken(),
                environment: "tests"
            )
            .set(serviceName: serviceName)
            .set(batchSize: .small)
            .set(uploadFrequency: .frequent)
            .set(sampleTelemetry: 100)

        if let customLogsURL = Environment.readCustomLogsURL() {
            _ = configuration.set(customLogsEndpoint: customLogsURL)
        }
        if let customTraceURL = Environment.readCustomTraceURL() {
            _ = configuration.set(customTracesEndpoint: customTraceURL)
        }
        if let customRUMURL = Environment.readCustomRUMURL() {
            _ = configuration.set(customRUMEndpoint: customRUMURL)
        }

        if let testScenario = testScenario {
            // If the `Example` app was launched with test scenario ENV, apply the scenario configuration
            testScenario.configureSDK(builder: configuration)
        } else {
            // Otherwise just enable all features so they can be tested with debug menu
            _ = configuration
                .enableLogging(true)
                .enableTracing(true)
                .enableRUM(true)
                .enableCrashReporting(using: DDCrashReportingPlugin())
                .trackBackgroundEvents()
        }

        return configuration.build()
    }

    func initialStoryboard() -> UIStoryboard? {
        if let testScenario = testScenario {
            return UIStoryboard(name: type(of: testScenario).storyboardName, bundle: nil)
        }
        #if os(iOS)
        return UIStoryboard(name: "Main iOS", bundle: nil)
        #else
        return nil
        #endif
    }
}

/// The configuration used when launching the Example app for Datadog SDK integration tests (⌘+U).
struct UITestsAppConfiguration: AppConfiguration {
    let testScenario: TestScenario? = Environment.testScenarioClassName()
        .flatMap { className in initializeTestScenario(with: className) }

    init() {
        if Environment.shouldClearPersistentData() {
            PersistenceHelpers.deleteAllSDKData()
        }

        // Handle messages received from UITest runner:
        try! MessagePortChannel.createReceiver().startListening { message in
            switch message {
            case .endRUMSession: markRUMSessionAsEnded()
            }
        }
    }

    var initialTrackingConsent: TrackingConsent {
        return testScenario!.initialTrackingConsent
    }

    func sdkConfiguration() -> Datadog.Configuration {
        let configuration = Datadog.Configuration
            .builderUsing(
                rumApplicationID: "rum-application-id",
                clientToken: "ui-tests-client-token",
                environment: "integration"
            )
            .set(serviceName: "ui-tests-service-name")
            .set(batchSize: .small)
            .set(uploadFrequency: .frequent)
            .set(tracingSamplingRate: 100)

        let serverMockConfiguration = Environment.serverMockConfiguration()

        // If `HTTPServerMock` endpoint is set for Logging, enable the feature and send data to mock server
        if let logsEndpoint = serverMockConfiguration?.logsEndpoint {
            _ = configuration.set(customLogsEndpoint: logsEndpoint)
        } else {
            _ = configuration.enableLogging(false)
        }

        // If `HTTPServerMock` endpoint is set for Tracing, enable the feature and send data to mock server
        if let tracesEndpoint = serverMockConfiguration?.tracesEndpoint {
            _ = configuration.set(customTracesEndpoint: tracesEndpoint)
        } else {
            _ = configuration.enableTracing(false)
        }

        // If `HTTPServerMock` endpoint is set for RUM, enable the feature and send data to mock server
        if let rumEndpoint = serverMockConfiguration?.rumEndpoint {
            _ = configuration.set(customRUMEndpoint: rumEndpoint)
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
}
