/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else {
            assertionFailure("Expected an application window scene")
            return
        }

        if let rootViewController = appConfiguration.testScenario?.makeRootViewController(
            for: windowScene,
            session: session,
            connectionOptions: connectionOptions
        ) {
            launch(rootViewController: rootViewController, in: windowScene)
            return
        }

        // Launch initial screen depending on the launch configuration.
        guard let storyboard = appConfiguration.initialStoryboard() else {
            assertionFailure("No initial storyboard defined in app configuration")
            return
        }

        launch(rootViewController: storyboard.instantiateInitialViewController()!, in: windowScene)
    }

    private func launch(rootViewController: UIViewController, in windowScene: UIWindowScene) {
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = rootViewController
        window.makeKeyAndVisible()
        self.window = window
    }
}
