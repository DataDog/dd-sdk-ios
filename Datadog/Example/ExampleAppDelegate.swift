/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import UIKit
import Datadog
import DatadogLogs
import DatadogTrace
import DatadogRUM
import DatadogCrashReporting

@_exported import enum DatadogInternal.TrackingConsent

let serviceName = "ios-sdk-example-app"

var logger: Logger!
var tracer: OTTracer { DatadogTracer.shared() }
var rumMonitor: RUMMonitorProtocol { RUMMonitor.shared() }

@UIApplicationMain
class ExampleAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if Environment.isRunningUnitTests() {
            return false
        }

        var configuration = Datadog.Configuration
            .builderUsing(
                rumApplicationID: Environment.readRUMApplicationID(),
                clientToken: Environment.readClientToken(),
                environment: "tests"
            )
            .set(serviceName: serviceName)
            .set(batchSize: .small)
            .set(uploadFrequency: .frequent)
            .set(sampleTelemetry: 100)

        if let customRUMURL = Environment.readCustomRUMURL() {
            configuration = configuration.set(customRUMEndpoint: customRUMURL)
        }

        // Enable all features so they can be tested with debug menu
        configuration = configuration
            .enableTracing(true)
            .enableRUM(true)
            .trackBackgroundEvents()

        // Initialize Datadog SDK
        Datadog.initialize(
            appContext: .init(),
            trackingConsent: .granted,
            configuration: configuration.build()
        )

        // Set user information
        Datadog.setUserInfo(id: "abcd-1234", name: "foo", email: "foo@example.com", extraInfo: ["key-extraUserInfo": "value-extraUserInfo"])

        // Create Logger
        logger = DatadogLogger.builder
            .set(loggerName: "logger-name")
            .sendNetworkInfo(true)
            .printLogsToConsole(true, usingFormat: .shortWith(prefix: "[iOS App] "))
            .build()

        logger.addAttribute(forKey: "device-model", value: UIDevice.current.model)

        #if DEBUG
        logger.addTag(withKey: "build_configuration", value: "debug")
        #else
        logger.addTag(withKey: "build_configuration", value: "release")
        #endif

        // Register Logs
        Logs.enable(
            with: Logs.Configuration(
                customIntakeURL: Environment.readCustomLogsURL()
            )
        )

        // Register Tracer
        DatadogTracer.initialize(
            configuration: DatadogTracer.Configuration(
                sendNetworkInfo: true,
                customIntakeURL: Environment.readCustomTraceURL()
            )
        )

        DatadogCrashReporter.initialize()

        // Set highest verbosity level to see debugging logs from the SDK
        Datadog.verbosityLevel = .debug

        // Enable RUM Views debugging
        RUMMonitor.shared().debug = true

        // Launch initial screen depending on the launch configuration
        #if os(iOS)
        let storyboard = UIStoryboard(name: "Main iOS", bundle: nil)
        launch(storyboard: storyboard)
        #endif

        #if !os(tvOS)
        // Instantiate location monitor if the Example app is run in interactive mode. This will
        // enable background location tracking if it was started in previous session.
        if Environment.isRunningInteractive() {
            backgroundLocationMonitor = BackgroundLocationMonitor(rum: rumMonitor)
        }
        #endif

        return true
    }

    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        installConsoleOutputInterceptor()
        return true
    }

    func launch(storyboard: UIStoryboard) {
        if window == nil {
            window = UIWindow(frame: UIScreen.main.bounds)
            window?.makeKeyAndVisible()
        }
        window?.rootViewController = storyboard.instantiateInitialViewController()!
    }
}
