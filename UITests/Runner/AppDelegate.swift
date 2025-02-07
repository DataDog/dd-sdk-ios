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

var serviceName = "integration-scenarios-service-name"
var appConfiguration: AppConfiguration!

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if Environment.isRunningUnitTests() {
            return false
        }

        appConfiguration = UITestsAppConfiguration()

        // Initialize Datadog SDK
        appConfiguration.initializeSDK()

        // Launch initial screen depending on the launch configuration
        if let storyboard = appConfiguration.initialStoryboard() {
            launch(storyboard: storyboard)
        }

        return true
    }

    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
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
