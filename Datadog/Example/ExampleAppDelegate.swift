/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import UIKit
import Datadog

var logger: Logger!
var tracer: OTTracer { Global.sharedTracer }
var rumMonitor: DDRUMMonitor { Global.rum }

var appConfiguration: AppConfiguration!

@UIApplicationMain
class ExampleAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if Environment.isRunningUnitTests() {
            return false
        } else if Environment.isRunningUITests() {
            appConfiguration = UITestsAppConfiguration()
        } else {
            appConfiguration = ExampleAppConfiguration()
        }

        // Initialize Datadog SDK
        Datadog.initialize(
            appContext: .init(),
            trackingConsent: appConfiguration.initialTrackingConsent,
            configuration: appConfiguration.sdkConfiguration()
        )

        // Set user information
        Datadog.setUserInfo(id: "abcd-1234", name: "foo", email: "foo@example.com", extraInfo: ["key-extraUserInfo": "value-extraUserInfo"])

        // Create Logger
        logger = Logger.builder
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

        // Register Tracer
        Global.sharedTracer = Tracer.initialize(
            configuration: Tracer.Configuration(
                sendNetworkInfo: true
            )
        )

        // Register RUMMonitor
        Global.rum = RUMMonitor.initialize()

        // Set highest verbosity level to see debugging logs from the SDK
        Datadog.verbosityLevel = .debug

        // Enable RUM Views debugging
        Datadog.debugRUM = true

        // Launch initial screen depending on the launch configuration
        if let storyboard = appConfiguration.initialStoryboard() {
            launch(storyboard: storyboard)
        }

        #if !os(tvOS)
        // Instantiate location monitor if the Example app is run in interactive mode. This will
        // enable background location tracking if it was started in previous session.
        if Environment.isRunningInteractive() {
            backgroundLocationMonitor = BackgroundLocationMonitor()
        }
        #endif

        return true
    }

    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        if appConfiguration is ExampleAppConfiguration {
            installConsoleOutputInterceptor()
        }
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

/// Bridges Swift objects to Objective-C.
@objcMembers
class SwiftGlobals: NSObject {
    class func currentTestScenario() -> Any? { appConfiguration.testScenario }
}
