/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2026-Present Datadog, Inc.
 */

import SwiftUI

@main
internal struct ProbeSwiftUIApp: App {
    @UIApplicationDelegateAdaptor(ProbeForwardingDelegate.self)
    private var delegate
    var body: some Scene {
        WindowGroup {
            ProbeScreen().onAppear { ProbeCapture.shared.postConnection(UIApplication.shared) }
        }
    }
}

internal final class ProbeForwardingDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        ProbeCapture.shared.start(application)
        return true
    }

    func application(
        _ application: UIApplication,
        didDiscardSceneSessions sessions: Set<UISceneSession>
    ) {
        ProbeCapture.shared.discard(sessions)
    }

    func applicationWillTerminate(_ application: UIApplication) { ProbeCapture.shared.terminate() }
}
