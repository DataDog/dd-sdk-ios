/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal var benchmarkRunner: BenchmarkRunner!

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        benchmarkRunner = BenchmarkRunner(app: self)
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {}

    func setFullScreenModal(viewController: UIViewController, completion: @escaping () -> Void = {}) {
        show(viewController: viewController, afterPresented: completion)
    }

    func dismissFullScreenModal(completion: @escaping () -> Void = {}) {
        goBackToMenu(afterPresented: completion)
    }

    /// Presents given view controller in as full screen modal.
    func show(viewController: UIViewController, afterPresented: @escaping () -> Void = {}) {
        viewController.modalPresentationStyle = .fullScreen

        // Present it from the next run-loop to avoid "Unbalanced calls to begin/end appearance transitions" warning:
        DispatchQueue.main.async {
            self.keyWindow?.rootViewController?.dismiss(animated: false) {
                self.keyWindow?.rootViewController?.present(viewController, animated: false) {
                    afterPresented()
                }
            }
        }
    }

    /// Goes back to app's root screen.
    func goBackToMenu(afterPresented: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.keyWindow?.rootViewController?.dismiss(animated: false) {
                afterPresented()
            }
        }
    }

    private var keyWindow: UIWindow? {
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
