/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import Datadog
import DatadogInternal
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
        guard let testScenario = testScenario else {
            return nil
        }
        return UIStoryboard(name: type(of: testScenario).storyboardName, bundle: nil)
    }
}
