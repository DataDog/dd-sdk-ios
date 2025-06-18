/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import SRFixtures

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {}

    /// Presents view controller for given fixture in full screen.
    func show(fixture: any FixtureProtocol, completion: @escaping (UIViewController) -> Void) {
        let vc = fixture.instantiateViewController()
        vc.modalPresentationStyle = .fullScreen

        // Present it from the next run-loop to avoid "Unbalanced calls to begin/end appearance transitions" warning:
        DispatchQueue.main.async {
            self.keyWindow?.rootViewController?.dismiss(animated: false) {
                self.keyWindow?.rootViewController?.present(vc, animated: false) {
                    completion(vc)
                }
            }
        }
    }

    var keyWindow: UIWindow? {
        if #available(iOS 15.0, *) {
            return UIApplication.shared
                .connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { scene in scene.windows.contains { window in window.isKeyWindow } }?
                .keyWindow
        } else {
            let application = UIApplication.value(forKeyPath: #keyPath(UIApplication.shared)) as? UIApplication // swiftlint:disable:this unsafe_uiapplication_shared
            return application?
                .connectedScenes
                .flatMap { ($0 as? UIWindowScene)?.windows ?? [] }
                .first { $0.isKeyWindow }
        }
    }
}
