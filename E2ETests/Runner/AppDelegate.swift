/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let info = try! TestInfo()
        let scenario: Scenario = ProcessInfo.processInfo.environment["E2E_SCENARIO"]
            .flatMap(Scenarios.init(rawValue:)) ?? DefaultScenario()

        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = scenario.start(info: info)
        window?.makeKeyAndVisible()
        return true
    }
}
