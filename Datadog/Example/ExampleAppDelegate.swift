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

var logger: LoggerProtocol!
var tracer: OTTracer { Tracer.shared() }
var rumMonitor: RUMMonitorProtocol { RUMMonitor.shared() }

@UIApplicationMain
class ExampleAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if Environment.isRunningUnitTests() {
            return false
        }

        let configuration = Datadog.Configuration
            .builderUsing(
                clientToken: Environment.readClientToken(),
                environment: "tests"
            )
            .set(serviceName: serviceName)
            .set(batchSize: .small)
            .set(uploadFrequency: .frequent)

        // Initialize Datadog SDK
        Datadog.initialize(
            appContext: .init(),
            trackingConsent: .granted,
            configuration: configuration.build()
        )

        // Set user information
        Datadog.setUserInfo(id: "abcd-1234", name: "foo", email: "foo@example.com", extraInfo: ["key-extraUserInfo": "value-extraUserInfo"])

        // Create Logger
        logger = Logger.create(
            with: Logger.Configuration(
                loggerName: "logger-name",
                sendNetworkInfo: true,
                consoleLogFormat: .shortWith(prefix: "[iOS App] ")
            )
        )

        logger.addAttribute(forKey: "device-model", value: UIDevice.current.model)

        #if DEBUG
        logger.addTag(withKey: "build_configuration", value: "debug")
        #else
        logger.addTag(withKey: "build_configuration", value: "release")
        #endif

        // Enable Logs
        Logs.enable(
            with: Logs.Configuration(
                customEndpoint: Environment.readCustomLogsURL()
            )
        )

        DatadogCrashReporter.initialize()

        // Set highest verbosity level to see debugging logs from the SDK
        Datadog.verbosityLevel = .debug

        // Enable Trace
        Trace.enable(
            with: Trace.Configuration(
                sendNetworkInfo: true,
                customEndpoint: Environment.readCustomTraceURL()
            )
        )

        // Enable RUM
        RUM.enable(
            with: RUM.Configuration(
                applicationID: Environment.readRUMApplicationID(),
                backgroundEventsTracking: true,
                customEndpoint: Environment.readCustomRUMURL(),
                telemetrySampleRate: 100
            )
        )
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
