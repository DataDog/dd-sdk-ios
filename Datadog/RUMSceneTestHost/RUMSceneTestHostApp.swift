/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

@main
@MainActor
final class RUMSceneTestHostAppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "RUM scene tests", sessionRole: session.role)
        configuration.delegateClass = RUMTestSceneDelegate.self
        return configuration
    }
}

@MainActor
final class RUMTestSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let root = UIViewController()
        root.view.backgroundColor = .systemBackground
        root.view.accessibilityIdentifier = "rum-scene-test-root"
        let owned = UIWindow(windowScene: windowScene)
        owned.accessibilityIdentifier = "rum-scene-test-window"
        owned.rootViewController = root
        window = owned
        owned.makeKeyAndVisible()
    }
}
