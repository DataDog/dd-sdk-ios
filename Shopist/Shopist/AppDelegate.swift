/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import Datadog

internal fileprivate(set) var logger: Logger! // swiftlint:disable:this implicitly_unwrapped_optional
internal let appConfig = AppConfig(serviceName: "io.shopist.ios")
internal let api = API()

internal struct ShopistPredicate: UIKitRUMViewsPredicate {
    func rumView(for viewController: UIViewController) -> RUMView? {
        if viewController is HomeViewController ||
            viewController is CatalogViewController ||
            viewController is ProductViewController ||
            viewController is CheckoutViewController {
            let attributes = viewController.isMovingToParent ? ["info": "Redisplay"] : [:]
            return RUMView(
                path: "\(type(of: viewController))",
                attributes: attributes
            )
        }
        return nil
    }
}

@UIApplicationMain
internal class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Initialize Datadog SDK
        Datadog.initialize(
            appContext: .init(),
            configuration: Datadog.Configuration
                .builderUsing(
                    rumApplicationID: appConfig.rumAppID,
                    clientToken: appConfig.clientToken,
                    environment: "shop.ist"
                )
                .set(serviceName: appConfig.serviceName)
                .track(firstPartyHosts: [API.baseHost])
                .trackUIKitActions(true)
                .trackUIKitRUMViews(using: ShopistPredicate())
                .build()
        )

        // Set user information
        let user = User.any()
        Datadog.setUserInfo(id: user.id, name: user.name, email: user.email)

        // Create logger instance
        logger = Logger.builder
            .printLogsToConsole(true, usingFormat: .shortWith(prefix: "[iOS App] "))
            .build()

        // Register global tracer
        Global.sharedTracer = Tracer.initialize(configuration: .init(serviceName: appConfig.serviceName))

        // Register global `RUMMonitor`
        Global.rum = RUMMonitor.initialize()
        // NOTE: usr.handle is used for historical reasons, it's deprecated in favor of usr.email
        Global.rum.addAttribute(forKey: "usr.handle", value: user.email)
        Global.rum.addAttribute(forKey: "hasPurchased", value: false)
        Global.rum.addAttribute(forKey: "network.override.client.ip", value: user.ipAddress)

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
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
