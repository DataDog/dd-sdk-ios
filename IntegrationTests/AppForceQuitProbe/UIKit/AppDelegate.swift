/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2026-Present Datadog, Inc.
 */

import SwiftUI
import UIKit

@main
internal final class ProbeAppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        ProbeCapture.shared.start(application)
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Probe", sessionRole: session.role)
        configuration.delegateClass = ProbeSceneDelegate.self
        return configuration
    }

    func application(
        _ application: UIApplication,
        didDiscardSceneSessions sessions: Set<UISceneSession>
    ) {
        ProbeCapture.shared.discard(sessions)
    }

    func applicationWillTerminate(_ application: UIApplication) { ProbeCapture.shared.terminate() }
}

internal final class ProbeSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) {
        guard let scene = scene as? UIWindowScene else {
            return
        }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: ProbeScreen())
        window.makeKeyAndVisible()
        self.window = window
        ProbeCapture.shared.scene(scene, event: "delegate_will_connect")
        ProbeCapture.shared.postConnection(UIApplication.shared)
    }
}
