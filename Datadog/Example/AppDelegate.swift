/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import UIKit
import Datadog

var logger: Logger!
var tracer: OTTracer { Global.sharedTracer }

let appConfig: AppConfig = currentAppConfig()

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        if isRunningUnitTests() {
            window = nil
            return false
        }

        if isRunningUITests() {
            deletePersistedSDKData()
        }

        // Initialize Datadog SDK
        Datadog.initialize(
            appContext: .init(),
            configuration: appConfig.datadogConfiguration
        )

        // Set user information
        Datadog.setUserInfo(id: "abcd-1234", name: "foo", email: "foo@example.com")

        // Create logger instance
        logger = Logger.builder
            .set(serviceName: appConfig.serviceName)
            .set(loggerName: "logger-name")
            .sendNetworkInfo(true)
            .printLogsToConsole(true, usingFormat: .shortWith(prefix: "[iOS App] "))
            .build()

        // Register global tracer
        Global.sharedTracer = DDTracer.initialize(
            configuration: DDTracer.Configuration(
                serviceName: appConfig.serviceName,
                sendNetworkInfo: true
            )
        )

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

        return true
    }

    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        installConsoleOutputInterceptor()
        return true
    }
}

private func isRunningUnitTests() -> Bool {
    return ProcessInfo.processInfo.arguments.contains("IS_RUNNING_UNIT_TESTS")
}

private func isRunningUITests() -> Bool {
    return appConfig is UITestAppConfig
}

private func deletePersistedSDKData() {
    guard let cachesDirectoryURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
        return
    }

    do {
        let dataDirectories = try FileManager.default
            .contentsOfDirectory(at: cachesDirectoryURL, includingPropertiesForKeys: [.isDirectoryKey, .canonicalPathKey])
            .filter { $0.absoluteString.contains("com.datadoghq") }

        try dataDirectories.forEach { url in
            try FileManager.default.removeItem(at: url)
            print("🧹 Deleted SDK data directory: \(url)")
        }
    } catch {
        print("🔥 Failed to delete SDK data directory: \(error)")
    }
}
