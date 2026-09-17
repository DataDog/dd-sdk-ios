/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import WebKit
import DatadogCore
import DatadogSessionReplay
import DatadogWebViewTracking
@_spi(Internal) import DatadogInternal
@testable import DatadogRUM

@MainActor
private enum Fixture {
    static var started = false
    static var checks: [String: Bool] = [:]
    static var details: [String: Any] = [:]
    static let runID = argument("--run-id")
    static let endpoint = argument("--endpoint")

    static func argument(_ name: String) -> String {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { return "" }
        return args[index + 1]
    }

    static func configure() {
        Datadog.initialize(
            with: .init(clientToken: "local-fixture-no-credentials", env: "webview-correlation", batchSize: .small, uploadFrequency: .frequent),
            trackingConsent: .granted
        )
        var configuration = RUM.Configuration(applicationID: "00000000-0000-0000-0000-000000000165")
        configuration.uiKitViewsPredicate = nil
        configuration.uiKitActionsPredicate = nil
        configuration.vitalsUpdateFrequency = nil
        configuration.trackSlowFrames = false
        configuration.trackFrustrations = false
        configuration.telemetrySampleRate = 0
        configuration.customEndpoint = URL(string: endpoint + "/rum")!
        RUM.enable(with: configuration)
        SessionReplay.enable(with: .init(replaySampleRate: 100, customEndpoint: URL(string: endpoint + "/replay")!))
    }

    static func drain(_ monitor: Monitor) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            monitor.currentSessionID { _ in continuation.resume() }
        }
    }

    static func replayEnabled() async -> Bool {
        await withCheckedContinuation { continuation in
            CoreRegistry.default.scope(for: RUMFeature.self).context { context in
                continuation.resume(returning: context.hasReplay == true)
            }
        }
    }

    static func browserEvent(_ label: String, in webView: WKWebView) async throws -> JSON {
        let browserID = UUID().uuidString.lowercased()
        let event: JSON = [
            "application": ["id": "browser-app"], "session": ["id": "browser-session", "has_replay": true],
            "view": ["id": browserID], "type": "view", "date": Int(Date().timeIntervalSince1970 * 1_000),
            "context": ["fixture_run_id": runID, "fixture_step": label]
        ]
        let message: JSON = ["eventType": "view", "event": event]
        let data = try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
        let string = String(data: data, encoding: .utf8)!
        let quoted = try JSONSerialization.data(withJSONObject: [string])
        let array = String(data: quoted, encoding: .utf8)!
        _ = try await webView.evaluateJavaScript("window.DatadogEventBridge.send(\(array)[0]); true")
        // Wait for this exact emitted browser payload before changing native ownership.
        // The collector never consumes acknowledgements, so readiness cannot be lost.
        for _ in 0..<300 {
            let (body, _) = try await URLSession.shared.data(from: URL(string: endpoint + "/event/" + browserID)!)
            if let value = try JSONSerialization.jsonObject(with: body) as? JSON, !value.isEmpty {
                checks[label + "_run_identity"] = (value["context"] as? JSON)?["fixture_run_id"] as? String == runID
                checks[label + "_private_metadata_removed"] = value["_dd.internal.native_scene_id"] == nil
                checks[label + "_replay_preserved"] = (value["session"] as? JSON)?["has_replay"] as? Bool == true
                return value
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw NSError(domain: "Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing emitted browser acknowledgement for " + label])
    }

    static func container(_ event: JSON) -> String? {
        ((event["container"] as? JSON)?["view"] as? JSON)?["id"] as? String
    }

    static func run(window: UIWindow, controller: UIViewController, webView: WKWebView) async {
        guard !started else { return }
        started = true
        do {
            guard let scene = window.windowScene, let monitor = RUMMonitor.shared() as? Monitor else {
                throw NSError(domain: "Fixture", code: 2)
            }
            checks["webview_mounted_in_native_scene"] = webView.window === window
            checks["single_native_scene"] = UIApplication.shared.connectedScenes.count == 1
            checks["declared_single_scene"] = (Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") as? JSON)?["UIApplicationSupportsMultipleScenes"] as? Bool == false
            details["native_scene_id"] = scene.session.persistentIdentifier
            details["peer_kind"] = "injected logical branch, not a second native window"
            // RUM's sampled session drives actual Replay enablement; wait for its context.
            for _ in 0..<100 {
                if await replayEnabled() { break }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            checks["actual_replay_enabled"] = await replayEnabled()
            guard checks["actual_replay_enabled"] == true else { throw NSError(domain: "Fixture", code: 3) }
            monitor.startView(key: "Legacy", name: "Legacy", attributes: ["fixture_run_id": runID])
            await drain(monitor)
            let legacyID = monitor.rumContextSnapshot(for: .processRepresentative)?.viewID
            checks["legacy_view_has_no_scene_owner"] = monitor.rumContextSnapshot(for: .scene(.init(rawValue: scene.session.persistentIdentifier))) == nil
            details["legacy_view_id"] = legacyID
            let legacyEvent = try await browserEvent("legacy", in: webView)
            checks["legacy_container_matches_native"] = legacyID != nil && container(legacyEvent) == legacyID

            RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: "fixture-peer-B") {
                monitor.startView(key: "Peer", name: "Peer", attributes: [:])
            }
            await drain(monitor)
            let peerID = monitor.rumContextSnapshot(for: .scene(.init(rawValue: "fixture-peer-B")))?.viewID
            checks["peer_branch_established"] = peerID != nil
            let peerEvent = try await browserEvent("peer", in: webView)
            checks["peer_container_omitted"] = container(peerEvent) == nil

            monitor.startView(viewController: controller, name: "Exact native", attributes: [:])
            await drain(monitor)
            let exactID = monitor.rumContextSnapshot(for: .scene(.init(rawValue: scene.session.persistentIdentifier)))?.viewID
            let exactEvent = try await browserEvent("exact", in: webView)
            checks["exact_container_matches_native"] = exactID != nil && container(exactEvent) == exactID
            checks["exact_does_not_use_peer"] = container(exactEvent) != peerID
            details["exact_view_id"] = exactID
            details["peer_view_id"] = peerID
            details["payloads"] = [legacyEvent, peerEvent, exactEvent]
        } catch {
            details["fixture_error"] = String(describing: error)
        }
        let result: JSON = ["run_id": runID, "checks": checks, "details": details]
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("result.json")
        try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: file, options: .atomic)
    }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Fixture.configure()
        return true
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate, WKNavigationDelegate {
    var window: UIWindow?
    private let controller = UIViewController()
    private var webView: WKWebView?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        self.window = window
        window.rootViewController = controller
        let webView = WKWebView(frame: window.bounds)
        self.webView = webView
        webView.navigationDelegate = self
        WebViewTracking.enable(webView: webView, hosts: ["localhost"])
        controller.view.addSubview(webView)
        window.makeKeyAndVisible()
        webView.loadHTMLString("<html><body>Legacy native WebView correlation</body></html>", baseURL: URL(string: "http://localhost"))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let window else { return }
        Task { await Fixture.run(window: window, controller: controller, webView: webView) }
    }
}
