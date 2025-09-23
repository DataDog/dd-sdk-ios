/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Launch initial screen depending on the launch configuration
        guard let storyboard = appConfiguration.initialStoryboard() else {
            assertionFailure("No initial storyboard defined in app configuration")
            return
        }

        launch(storyboard: storyboard, in: scene)
    }

    func launch(storyboard: UIStoryboard, in scene: UIScene) {
        let window = UIWindow(windowScene: scene as! UIWindowScene)
        window.rootViewController = storyboard.instantiateInitialViewController()!
        window.makeKeyAndVisible()
        self.window = window
    }
}
