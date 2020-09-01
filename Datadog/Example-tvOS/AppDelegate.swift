/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import UIKit
import Datadog_tvOS

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // Initialize Datadog SDK
        Datadog.initialize(
            appContext: .init(),
            configuration: tvOSAppConfig().datadogConfiguration
        )

        // Set user information
        Datadog.setUserInfo(id: "abcd-1234", name: "foo", email: "foo@example.com")

        // Create RUM monitor instance
        Global.rum = RUMMonitor.initialize()

        // Enable RUM Views debug utility.
        Datadog.debugRUM = true

        return true
    }
}
