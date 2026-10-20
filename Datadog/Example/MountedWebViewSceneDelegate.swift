/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */
#if os(iOS) && DD_MOUNTED_WEBVIEW_ACCEPTANCE
import UIKit

@available(iOS 27.0, *)
@MainActor
final class MountedWebViewSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene,
              ProcessInfo.processInfo.arguments.contains("IS_RUNNING_UNIT_TESTS"),
              let run = ProcessInfo.processInfo.environment["DD_MOUNTED_WEBVIEW_RUN_ID"],
              UUID(uuidString: run) != nil else { return }
        let request = options.userActivities.first { $0.activityType == "com.datadoghq.mounted-webview" }
        let label = request?.userInfo?["window"] as? String ?? "A"
        guard ["A", "B"].contains(label),
              request == nil || request?.userInfo?["run"] as? String == run else { return }
        let root = UIViewController()
        root.view.backgroundColor = .systemBackground
        root.view.accessibilityIdentifier = "mounted-webview-root:" + run + ":" + label
        let owned = UIWindow(windowScene: windowScene)
        owned.accessibilityIdentifier = "mounted-webview-window:" + run + ":" + label
        owned.rootViewController = root
        window = owned
        owned.makeKeyAndVisible()
        NotificationCenter.default.post(
            name: Notification.Name("MountedWebViewWindowConnected"),
            object: owned,
            userInfo: ["run": run, "window": label, "scene": session.persistentIdentifier]
        )
    }
}
#endif
