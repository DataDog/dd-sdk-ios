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

private struct User {
    let id: String = UUID().uuidString
    let name: String
    var email: String {
        return name.lowercased()
            .replacingOccurrences(of: " ", with: "@")
            .appending(".com")
    }

    static let users: [User] = [
        User(name: "John Doe"),
        User(name: "Jane Doe"),
        User(name: "Pat Doe"),
        User(name: "Sam Doe"),
        User(name: "Maynard Keenan"),
        User(name: "Adam Jones"),
        User(name: "Justin Chancellor"),
        User(name: "Danny Carey"),
        User(name: "Karina Round"),
        User(name: "Martin Lopez"),
        User(name: "Anneke Giersbergen"),
        User(name: "Billie Eilish"),
        User(name: "Cardi B"),
        User(name: "Nicki Minaj"),
        User(name: "Beyonce Knowles")
    ]

    private static let userDefaultsUserIndexKey = "shopist.currentUser.index"
    static func any() -> Self {
        let index = UserDefaults.standard.integer(forKey: userDefaultsUserIndexKey)
        let user = users[index % users.count]
        UserDefaults.standard.set(index + 1, forKey: userDefaultsUserIndexKey)
        return user
    }
}

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
