/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogCore
import DatadogLogs
import DatadogTrace
import DatadogRUM
import DatadogCrashReporting

var logger: LoggerProtocol?
var rumMonitor: RUMMonitorProtocol { RUMMonitor.shared() }

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
        var configuration = Datadog.Configuration(
            clientToken: "ui-tests-client-token",
            env: "integration",
            service: "ui-tests-service-name",
            batchSize: .small,
            uploadFrequency: .frequent
        )

        // Apply the scenario configuration
        testScenario?.override(configuration: &configuration)

        return configuration
    }

    func initialStoryboard() -> UIStoryboard? {
        guard let testScenario = testScenario else {
            return nil
        }
        return UIStoryboard(name: type(of: testScenario).storyboardName, bundle: nil)
    }
}

extension AppConfiguration {
    func initializeSDK() {
        // Initialize Datadog SDK
        Datadog.initialize(
            with: appConfiguration.sdkConfiguration(),
            trackingConsent: appConfiguration.initialTrackingConsent
        )

        appConfiguration.testScenario?.configureFeatures()

        // Set user information
        Datadog.setUserInfo(id: "abcd-1234", name: "foo", email: "foo@example.com", extraInfo: ["key-extraUserInfo": "value-extraUserInfo"])

        // Create Logger
        logger = Logger.create(
            with: Logger.Configuration(
                name: "logger-name",
                networkInfoEnabled: true,
                consoleLogFormat: .shortWith(prefix: "[iOS App] ")
            )
        )

        logger?.addAttribute(forKey: "device-model", value: UIDevice.current.model)

        #if DEBUG
        logger?.addTag(withKey: "build_configuration", value: "debug")
        #else
        logger?.addTag(withKey: "build_configuration", value: "release")
        #endif

        // Set highest verbosity level to see debugging logs from the SDK
        Datadog.verbosityLevel = .debug

        // Enable RUM Views debugging
        RUMMonitor.shared().debug = true
    }

    func deinitializeSDK() {
        Datadog.stopInstance()
        logger = nil
    }
}
