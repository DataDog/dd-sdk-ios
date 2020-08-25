/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import Datadog

internal fileprivate(set) var logger: Logger! // swiftlint:disable:this implicitly_unwrapped_optional
internal let appConfig = AppConfig(serviceName: "ios-sdk-shopist-app")
var rum: DDRUMMonitor? { Global.rum }

@UIApplicationMain
internal class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Initialize Datadog SDK
        Datadog.initialize(
            appContext: .init(),
            configuration: Datadog.Configuration
                .builderUsing(
                    rumApplicationID: appConfig.rumAppID,
                    clientToken: appConfig.rumClientToken,
                    environment: "tests"
                )
                .build()
        )

        // Set user information
        Datadog.setUserInfo(id: "abcd-1234", name: "foo", email: "foo@example.com")

        // Create logger instance
        logger = Logger.builder
            .set(serviceName: appConfig.serviceName)
            .printLogsToConsole(true, usingFormat: .shortWith(prefix: "[iOS App] "))
            .build()

        // Register global tracer
        Global.sharedTracer = Tracer.initialize(configuration: .init(serviceName: appConfig.serviceName))

        // Register global `RUMMonitor`
        Global.rum = RUMMonitor.initialize()

        // Set highest verbosity level to see internal actions made in SDK
        Datadog.verbosityLevel = .debug

        // Add attributes
        logger.addAttribute(forKey: "device-model", value: UIDevice.current.model)

        // Add tags
        #if DEBUG
        logger.addTag(withKey: "build_configuration", value: "debug")
        #else
        logger.addTag(withKey: "build_configuration", value: "release")
        #endif

        // Send some logs 🚀
        logger.info("application did finish launching")

        return true
    }

    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
}
